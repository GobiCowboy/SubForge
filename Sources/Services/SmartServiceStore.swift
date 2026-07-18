import Foundation
import StoreKit

enum SmartPurchaseError: LocalizedError {
    case productUnavailable
    case invalidOrder
    case keychainSaveFailed
    case verificationFailed
    case server(String)

    var errorDescription: String? {
        switch self {
        case .productUnavailable: "App Store 暂时无法提供该商品"
        case .invalidOrder: "购买订单数据无效"
        case .keychainSaveFailed: "无法将官方服务凭证安全保存到钥匙串"
        case .verificationFailed: "StoreKit 交易验证失败"
        case .server(let code): "购买服务错误：\(code)"
        }
    }
}

private struct AppleOrderResponse: Decodable {
    let orderId: String
    let appleProductId: String
    let appAccountToken: String
    let apiKey: String
}

private struct BillingOrderResponse: Decodable {
    let status: String
}

private struct BillingErrorResponse: Decodable {
    let error: String
}

@MainActor
final class SmartServiceStore: ObservableObject {
    @Published private(set) var balanceSeconds = 0
    @Published private(set) var productPrice: String?
    @Published private(set) var statusMessage = "尚未购买智能字幕时长"
    @Published private(set) var isLoading = false
    @Published private(set) var isPurchasing = false

    private let profile = OfficialServiceConfiguration.activeProfile
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    var balanceText: String {
        let minutes = balanceSeconds / 60
        let seconds = balanceSeconds % 60
        return seconds == 0 ? "\(minutes) 分钟" : "\(minutes) 分 \(seconds) 秒"
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        await loadProductPrice()
        await refreshWallet()
    }

    func refreshWallet() async {
        guard let key = KeychainStore.read(.officialServiceKey), !key.isEmpty else {
            balanceSeconds = 0
            statusMessage = "尚未购买智能字幕时长"
            return
        }
        do {
            let wallet = try await OfficialSmartServiceClient(
                profile: profile,
                apiKey: key,
                session: session
            ).wallet()
            balanceSeconds = wallet.balanceSeconds
            statusMessage = wallet.balanceSeconds > 0 ? "官方智能服务已就绪" : "额度已用完，可继续购买"
        } catch {
            statusMessage = "凭证已保存，等待购买入账"
        }
    }

    @discardableResult
    func purchase300Minutes() async -> Bool {
        guard !isPurchasing else { return false }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            statusMessage = "正在准备 App Store 订单…"
            let order = try await createOrder(existingKey: KeychainStore.read(.officialServiceKey))
            guard KeychainStore.save(order.apiKey, account: .officialServiceKey) else {
                throw SmartPurchaseError.keychainSaveFailed
            }
            guard let accountToken = UUID(uuidString: order.appAccountToken) else {
                throw SmartPurchaseError.invalidOrder
            }
            let products = try await Product.products(for: [order.appleProductId])
            guard let product = products.first(where: { $0.id == order.appleProductId }) else {
                throw SmartPurchaseError.productUnavailable
            }
            productPrice = product.displayPrice
            let result = try await product.purchase(options: [.appAccountToken(accountToken)])
            switch result {
            case .success(.verified(let transaction)):
                guard transaction.productID == order.appleProductId else {
                    throw SmartPurchaseError.verificationFailed
                }
                await transaction.finish()
                statusMessage = "购买已完成，等待 Apple 服务端通知…"
                let paid = try await waitForFulfillment(orderID: order.orderId)
                if paid {
                    await refreshWallet()
                    return true
                }
                statusMessage = "购买已完成，额度正在到账，请稍后刷新"
            case .success(.unverified):
                throw SmartPurchaseError.verificationFailed
            case .pending:
                statusMessage = "购买等待批准，批准后会自动入账"
            case .userCancelled:
                statusMessage = "已取消购买"
            @unknown default:
                throw SmartPurchaseError.verificationFailed
            }
        } catch {
            statusMessage = error.localizedDescription
        }
        return false
    }

    private func loadProductPrice() async {
        guard let product = try? await Product.products(
            for: [OfficialServiceConfiguration.appleProductID]
        ).first else { return }
        productPrice = product.displayPrice
    }

    private func createOrder(existingKey: String?) async throws -> AppleOrderResponse {
        let url = profile.billingBaseURL.appending(path: "v1/apple/orders")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body = ["productId": OfficialServiceConfiguration.internalProductID]
        if let existingKey, !existingKey.isEmpty { body["existingApiKey"] = existingKey }
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 30
        return try await send(request)
    }

    private func waitForFulfillment(orderID: String) async throws -> Bool {
        for _ in 0..<90 {
            try Task.checkCancellation()
            let url = profile.billingBaseURL.appending(path: "v1/orders/\(orderID)")
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            let order: BillingOrderResponse = try await send(request)
            if order.status == "paid" { return true }
            try await Task.sleep(for: .seconds(2))
        }
        return false
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SmartPurchaseError.invalidOrder }
        guard (200..<300).contains(http.statusCode) else {
            let code = (try? JSONDecoder().decode(BillingErrorResponse.self, from: data).error) ?? "HTTP_\(http.statusCode)"
            throw SmartPurchaseError.server(code)
        }
        guard let value = try? JSONDecoder().decode(T.self, from: data) else {
            throw SmartPurchaseError.invalidOrder
        }
        return value
    }
}
