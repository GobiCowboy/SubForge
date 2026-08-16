import Foundation
import StoreKit

@MainActor
extension SmartServiceStore {
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
            if case .unavailable = KeychainStore.readResult(.officialServiceKey) {
                throw SmartPurchaseError.keychainUnavailable
            }
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

    func loadProductPrice() async {
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

    func reportKeychainUnavailable(_ status: OSStatus) {
        statusMessage = "无法访问官方服务凭证（钥匙串状态 \(status)）。请打开正式版 App，或在系统钥匙串中允许 SubForge 访问。"
        AppLog.settings.error(
            "officialServiceKeychainUnavailable status=\(status, privacy: .public)"
        )
    }

    func createOrder(
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

    func claimTrial(signedAppTransaction: String) async throws -> AppleTrialResponse {
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

    enum ReconciliationResult {
        case paid
        case pending
        case unavailable
    }
}
