import Foundation
import StoreKit

enum SmartPurchaseError: LocalizedError {
    case productUnavailable
    case invalidOrder
    case keychainSaveFailed
    case verificationFailed
    case appTransactionUnavailable
    case keychainUnavailable
    case server(String)

    var errorDescription: String? {
        switch self {
        case .productUnavailable: "App Store 暂时无法提供该商品"
        case .invalidOrder: "购买订单数据无效"
        case .keychainSaveFailed: "无法将官方服务凭证安全保存到钥匙串"
        case .verificationFailed: "StoreKit 交易验证失败"
        case .appTransactionUnavailable: "暂时无法验证本次 App Store 安装"
        case .keychainUnavailable: "无法访问官方服务凭证，请打开正式版 App 或在系统钥匙串中允许 SubForge 访问"
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

struct AppleOrderResponse: Decodable {
    let orderId: String
    let appleProductId: String
    let appAccountToken: String
    let apiKey: String
}

struct BillingOrderResponse: Decodable {
    let status: String
}

struct AppleReconciliationResponse: Decodable {
    let orderId: String
    let status: String
}

struct BillingErrorResponse: Decodable {
    let error: String
}

struct AppleTrialResponse: Decodable {
    let apiKey: String
    let granted: Bool
    let trialSeconds: Int
}

@MainActor
final class SmartServiceStore: ObservableObject {
    @Published var balanceSeconds = 0
    @Published var productPrices: [OfficialPurchasePlan: String] = [:]
    @Published var productCatalogMessage: String?
    @Published var hasLoadedProductCatalog = false
    @Published var statusMessage = "尚未购买智能字幕时长"
    @Published var isLoading = false
    @Published var isRefreshingWallet = false
    @Published var isPurchasing = false

    let profile = OfficialServiceConfiguration.activeProfile
    let session: URLSession
    var hasLoaded = false
    var isReconcilingTransactions = false

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
        switch KeychainStore.readResult(.officialServiceKey) {
        case .notFound:
            _ = await activateTrialIfNeeded()
        case .value:
            await refreshWalletBalance()
        case .unavailable(let status):
            reportKeychainUnavailable(status)
        }
    }

    func refreshWallet() async {
        guard !isRefreshingWallet else { return }
        isRefreshingWallet = true
        statusMessage = "正在查询最新额度…"
        defer { isRefreshingWallet = false }

        await reconcileUnconfirmedAppleTransactions()
        await refreshWalletBalance()
    }

    func reconcilePurchasesAtLaunch() async {
        await reconcileUnconfirmedAppleTransactions()
    }

    func refreshWalletBalance() async {
        let key: String
        switch KeychainStore.readResult(.officialServiceKey) {
        case .notFound:
            balanceSeconds = 0
            statusMessage = "尚未购买智能字幕时长"
            return
        case .unavailable(let status):
            reportKeychainUnavailable(status)
            return
        case .value(let value):
            guard !value.isEmpty else {
                balanceSeconds = 0
                statusMessage = "尚未购买智能字幕时长"
                return
            }
            key = value
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
        switch KeychainStore.readResult(.officialServiceKey) {
        case .value(let key) where !key.isEmpty:
            await refreshWallet()
            return .notNeeded
        case .unavailable(let status):
            reportKeychainUnavailable(status)
            return .unavailable(statusMessage)
        case .value, .notFound:
            break
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

}
