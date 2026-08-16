import Foundation
import StoreKit

@MainActor
extension SmartServiceStore {
    func reconcileAppleTransaction(_ transactionID: String) async -> ReconciliationResult {
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

    func reconcileUnconfirmedAppleTransactions() async {
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

    func waitForFulfillment(orderID: String, transactionID: String) async throws -> Bool {
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

    func send<T: Decodable>(_ request: URLRequest) async throws -> T {
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
