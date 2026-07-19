import Foundation
import StoreKit

enum SmartPurchaseError: LocalizedError {
    case productUnavailable
    case invalidOrder
    case keychainSaveFailed
    case verificationFailed
    case appTransactionUnavailable
    case server(String)

    var errorDescription: String? {
        switch self {
        case .productUnavailable: "App Store 暂时无法提供该商品"
        case .invalidOrder: "购买订单数据无效"
        case .keychainSaveFailed: "无法将官方服务凭证安全保存到钥匙串"
        case .verificationFailed: "StoreKit 交易验证失败"
        case .appTransactionUnavailable: "暂时无法验证本次 App Store 安装"
        case .server(let code): "购买服务错误：\(code)"
        }
    }
}

enum SmartTrialActivation: Equatable {
    case notNeeded
    case granted(Int)
    case restored(Int)
    case unavailable(String)
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

private struct AppleReconciliationResponse: Decodable {
    let orderId: String
    let status: String
}

private struct BillingErrorResponse: Decodable {
    let error: String
}

private struct AppleTrialResponse: Decodable {
    let apiKey: String
    let granted: Bool
    let trialSeconds: Int
}

@MainActor
final class SmartServiceStore: ObservableObject {
    @Published private(set) var balanceSeconds = 0
    @Published private(set) var productPrices: [OfficialPurchasePlan: String] = [:]
    @Published private(set) var productCatalogMessage: String?
    @Published private(set) var hasLoadedProductCatalog = false
    @Published private(set) var statusMessage = "尚未购买智能字幕时长"
    @Published private(set) var isLoading = false
    @Published private(set) var isPurchasing = false

    private let profile = OfficialServiceConfiguration.activeProfile
    private let session: URLSession
    private var hasLoaded = false
    private var isReconcilingTransactions = false

    init(session: URLSession = .shared) {
        self.session = session
    }

    var balanceText: String {
        let minutes = balanceSeconds / 60
        let seconds = balanceSeconds % 60
        return seconds == 0 ? "\(minutes) 分钟" : "\(minutes) 分 \(seconds) 秒"
    }

    func price(for plan: OfficialPurchasePlan) -> String? {
        productPrices[plan]
    }

    func priceText(for plan: OfficialPurchasePlan) -> String {
        if let price = productPrices[plan] { return price }
        return hasLoadedProductCatalog ? "暂不可用" : "加载中"
    }

    func load(force: Bool = false) async {
        guard !isLoading, force || !hasLoaded else { return }
        hasLoaded = true
        isLoading = true
        defer { isLoading = false }
        await loadProductPrice()
        await reconcileUnconfirmedAppleTransactions()
        if KeychainStore.read(.officialServiceKey) == nil {
            _ = await activateTrialIfNeeded()
        } else {
            await refreshWalletBalance()
        }
    }

    func refreshWallet() async {
        await reconcileUnconfirmedAppleTransactions()
        await refreshWalletBalance()
    }

    func reconcilePurchasesAtLaunch() async {
        await reconcileUnconfirmedAppleTransactions()
    }

    private func refreshWalletBalance() async {
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

    /// App Store signs one stable app transaction per Apple Account and app.
    /// Billing verifies that JWS and Model API derives an idempotent trial wallet
    /// from its one-way digest, so reinstalling cannot create extra trial time.
    func activateTrialIfNeeded() async -> SmartTrialActivation {
        if let key = KeychainStore.read(.officialServiceKey), !key.isEmpty {
            await refreshWallet()
            return .notNeeded
        }

        do {
            let verification = try await Self.loadWithRefreshFallback(
                shared: { try await AppTransaction.shared },
                refresh: { try await AppTransaction.refresh() },
                onSharedFailure: { error in
                    AppLog.settings.warning(
                        "AppTransaction.shared failed; refreshing error=\(error.localizedDescription, privacy: .public)"
                    )
                }
            )
            guard case .verified = verification else {
                throw SmartPurchaseError.verificationFailed
            }
            let trial = try await claimTrial(
                signedAppTransaction: verification.jwsRepresentation
            )
            guard KeychainStore.save(trial.apiKey, account: .officialServiceKey) else {
                throw SmartPurchaseError.keychainSaveFailed
            }
            await refreshWallet()
            return trial.granted
                ? .granted(trial.trialSeconds)
                : .restored(trial.trialSeconds)
        } catch {
            let message = error.localizedDescription
            statusMessage = message
            return .unavailable(message)
        }
    }

    /// StoreKit recommends refreshing the signed app transaction when its cached
    /// `shared` value is unavailable (for example, a fresh TestFlight install).
    static func loadWithRefreshFallback<T>(
        shared: () async throws -> T,
        refresh: () async throws -> T,
        onSharedFailure: ((Error) -> Void)? = nil
    ) async throws -> T {
        do {
            return try await shared()
        } catch {
            onSharedFailure?(error)
            return try await refresh()
        }
    }

    @discardableResult
    func purchase300Minutes() async -> Bool {
        await purchase(plan: .standard)
    }

    @discardableResult
    func purchase(plan: OfficialPurchasePlan) async -> Bool {
        guard !isPurchasing else { return false }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            statusMessage = "正在连接 App Store…"
            let products = try await Product.products(for: [plan.appleProductID])
            guard let product = products.first(where: { $0.id == plan.appleProductID }) else {
                productCatalogMessage = "TestFlight 未返回该内购商品，请检查 App Store Connect 商品状态与测试账号。"
                throw SmartPurchaseError.productUnavailable
            }
            productPrices[plan] = product.displayPrice
            productCatalogMessage = nil

            statusMessage = "正在准备购买订单…"
            let order = try await createOrder(
                plan: plan,
                existingKey: KeychainStore.read(.officialServiceKey)
            )
            guard KeychainStore.save(order.apiKey, account: .officialServiceKey) else {
                throw SmartPurchaseError.keychainSaveFailed
            }
            guard let accountToken = UUID(uuidString: order.appAccountToken) else {
                throw SmartPurchaseError.invalidOrder
            }
            guard product.id == order.appleProductId else {
                throw SmartPurchaseError.invalidOrder
            }
            statusMessage = "正在打开 Apple 购买窗口…"
            let result = try await product.purchase(options: [.appAccountToken(accountToken)])
            switch result {
            case .success(.verified(let transaction)):
                guard transaction.productID == order.appleProductId else {
                    throw SmartPurchaseError.verificationFailed
                }
                let transactionID = String(transaction.id)
                statusMessage = "购买已完成，正在确认到账…"
                if await reconcileAppleTransaction(transactionID) == .paid {
                    AppleTransactionReconciliationStore.markReconciled(transactionID)
                    await transaction.finish()
                    await refreshWalletBalance()
                    return true
                }
                let paid = try await waitForFulfillment(
                    orderID: order.orderId,
                    transactionID: transactionID
                )
                if paid {
                    AppleTransactionReconciliationStore.markReconciled(transactionID)
                    await transaction.finish()
                    await refreshWalletBalance()
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
            AppLog.settings.error(
                "storeKitPurchaseFailed product=\(plan.appleProductID, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
        }
        return false
    }

    private func loadProductPrice() async {
        do {
            let products = try await Product.products(
                for: OfficialServiceConfiguration.purchasePlans.map(\.appleProductID)
            )
            hasLoadedProductCatalog = true
            for plan in OfficialServiceConfiguration.purchasePlans {
                if let product = products.first(where: { $0.id == plan.appleProductID }) {
                    productPrices[plan] = product.displayPrice
                }
            }
            let missing = OfficialServiceConfiguration.purchasePlans.filter { productPrices[$0] == nil }
            productCatalogMessage = missing.isEmpty
                ? nil
                : "部分内购商品暂不可用；点击购买会重新向 App Store 查询。"
            AppLog.settings.info(
                "storeKitProductsLoaded requested=\(OfficialServiceConfiguration.purchasePlans.count, privacy: .public) returned=\(products.count, privacy: .public)"
            )
        } catch {
            hasLoadedProductCatalog = true
            productCatalogMessage = "无法连接 App Store：\(error.localizedDescription)"
            AppLog.settings.error(
                "storeKitProductsLoadFailed error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func createOrder(
        plan: OfficialPurchasePlan,
        existingKey: String?
    ) async throws -> AppleOrderResponse {
        let url = profile.billingBaseURL.appending(path: "v1/apple/orders")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = OfficialServiceConfiguration.purchaseOrderBody(
            plan: plan,
            existingKey: existingKey
        )
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 30
        return try await send(request)
    }

    private func claimTrial(signedAppTransaction: String) async throws -> AppleTrialResponse {
        guard !signedAppTransaction.isEmpty else {
            throw SmartPurchaseError.appTransactionUnavailable
        }
        let url = profile.billingBaseURL.appending(path: "v1/apple/trials")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "applicationId": OfficialServiceConfiguration.applicationID,
            "signedAppTransaction": signedAppTransaction
        ])
        request.timeoutInterval = 30
        return try await send(request)
    }

    private enum ReconciliationResult {
        case paid
        case pending
        case unavailable
    }

    private func reconcileAppleTransaction(_ transactionID: String) async -> ReconciliationResult {
        let url = profile.billingBaseURL.appending(path: "v1/apple/reconcile")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode([
            "applicationId": OfficialServiceConfiguration.applicationID,
            "transactionId": transactionID
        ])
        request.timeoutInterval = 30
        do {
            let response: AppleReconciliationResponse = try await send(request)
            return response.status == "paid" ? .paid : .pending
        } catch SmartPurchaseError.server(let code) where code == "APPLE_RECONCILIATION_UNAVAILABLE" {
            return .unavailable
        } catch {
            AppLog.settings.warning(
                "applePurchaseReconciliationFailed error=\(error.localizedDescription, privacy: .public)"
            )
            return .pending
        }
    }

    private func reconcileUnconfirmedAppleTransactions() async {
        guard !isReconcilingTransactions else { return }
        isReconcilingTransactions = true
        defer { isReconcilingTransactions = false }

        let known = AppleTransactionReconciliationStore.reconciledIDs()
        let supportedProducts = Set(OfficialServiceConfiguration.purchasePlans.map(\.appleProductID))
        var candidates: [Transaction] = []
        for await result in Transaction.all {
            guard case .verified(let transaction) = result,
                  supportedProducts.contains(transaction.productID),
                  transaction.revocationDate == nil,
                  !known.contains(String(transaction.id)) else { continue }
            candidates.append(transaction)
        }

        AppLog.settings.info(
            "applePurchaseReconciliationStarted candidates=\(candidates.count, privacy: .public)"
        )

        for transaction in candidates.sorted(by: { $0.purchaseDate > $1.purchaseDate }).prefix(50) {
            let transactionID = String(transaction.id)
            switch await reconcileAppleTransaction(transactionID) {
            case .paid:
                AppleTransactionReconciliationStore.markReconciled(transactionID)
                await transaction.finish()
                AppLog.settings.info("applePurchaseReconciliationCompleted")
            case .pending:
                continue
            case .unavailable:
                return
            }
        }
    }

    private func waitForFulfillment(orderID: String, transactionID: String) async throws -> Bool {
        var reconciliationUnavailable = false
        for attempt in 0..<20 {
            try Task.checkCancellation()
            let url = profile.billingBaseURL.appending(path: "v1/orders/\(orderID)")
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            let order: BillingOrderResponse = try await send(request)
            if order.status == "paid" { return true }
            if !reconciliationUnavailable, (attempt == 4 || attempt == 12) {
                switch await reconcileAppleTransaction(transactionID) {
                case .paid:
                    return true
                case .pending:
                    break
                case .unavailable:
                    reconciliationUnavailable = true
                }
            }
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
