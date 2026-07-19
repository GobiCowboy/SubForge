import Foundation
import Testing
@testable import SubForge

@Test func officialServiceEnablesOnlyChinaProfile() {
    let china = OfficialServiceConfiguration.profile(for: .china)
    #expect(china?.processingRegion == "china")
    #expect(china?.billingBaseURL.scheme == "https")
    #expect(china?.modelBaseURL.path == "/v1")
    #expect(OfficialServiceConfiguration.profile(for: .international) == nil)
}

@Test func officialServiceMapsAppLocalesToProviderLanguages() {
    #expect(OfficialSmartServiceClient.providerLanguage("zh-CN") == "zh")
    #expect(OfficialSmartServiceClient.providerLanguage("en-US") == "en")
    #expect(OfficialSmartServiceClient.providerLanguage("zh-CN,en-US") == "zh")
}

@Test func officialProductIdentifiersStayAligned() {
    #expect(OfficialServiceConfiguration.applicationID == "subforge")
    #expect(OfficialServiceConfiguration.internalProductID == "subforge_smart_300")
    #expect(OfficialServiceConfiguration.appleProductID == "com.jago.subforge.smart.300min")
    #expect(OfficialPurchasePlan.starter.appleProductID == "com.jago.subforge.smart.60min")
    #expect(OfficialPurchasePlan.starter.internalProductID == "subforge_smart_60")
    #expect(OfficialPurchasePlan.starter.minutes == 60)
    #expect(OfficialPurchasePlan.standard.minutes == 300)
}

@Test func officialPurchaseOrderIncludesApplicationIdentity() {
    let body = OfficialServiceConfiguration.purchaseOrderBody(
        plan: .standard,
        existingKey: "wallet-key"
    )

    #expect(body["applicationId"] == "subforge")
    #expect(body["productId"] == "subforge_smart_300")
    #expect(body["existingApiKey"] == "wallet-key")
}

@Test func officialTaskPollingRetriesOnlyRecoverableFailures() {
    #expect(OfficialSmartServiceClient.shouldRetryPolling(OfficialSmartServiceError.transientService(503)))
    #expect(OfficialSmartServiceClient.shouldRetryPolling(URLError(.timedOut)))
    #expect(OfficialSmartServiceClient.shouldRetryPolling(URLError(.networkConnectionLost)))
    #expect(!OfficialSmartServiceClient.shouldRetryPolling(OfficialSmartServiceError.activeTaskExists))
    #expect(!OfficialSmartServiceClient.shouldRetryPolling(URLError(.badURL)))
}

@Test func officialTaskStatusSeparatesASRAndProofreadingProgress() {
    #expect(OfficialSmartServiceClient.progressPhase(forTaskStatus: "processing") == .transcribing)
    #expect(OfficialSmartServiceClient.progressPhase(forTaskStatus: "proofreading") == .proofreading)
    #expect(OfficialSmartServiceClient.progressPhase(forTaskStatus: "completed") == .finishing)
}

@MainActor
@Test func officialSmartPipelineUsesFourUserFacingStages() {
    let titles = AppModel.makePipelineStages(
        proofreadingEnabled: true,
        officialSmart: true
    ).map(\.title)

    #expect(titles == ["准备上传", "语音转写", "智能校对", "完成字幕"])
}

@Test func officialSmartResultsUseSharedSubtitleLengthLimit() {
    let input = [
        SubtitleSegment(
            start: 0,
            end: 8,
            text: "这是一段需要按照公共字数限制重新切分的官方智能字幕结果"
        ),
        SubtitleSegment(
            start: 8.1,
            end: 12,
            text: "Supercalifragilisticexpialidocious"
        )
    ]

    let output = OfficialSmartSubtitleProvider.applySegmentation(
        input,
        configuration: SubtitleSegmentationConfiguration(maxCharacters: 10)
    )

    #expect(output.count > 1)
    #expect(output.filter { $0.text != "Supercalifragilisticexpialidocious" }.allSatisfy { $0.text.count <= 10 })
    #expect(output.contains { $0.text == "Supercalifragilisticexpialidocious" })
    #expect(output.first?.start == 0)
    #expect(output.last.map { $0.end <= 12.01 } == true)
}

@Test func officialWalletUsesSeparateLocalAndAppStoreKeychainServices() {
    let local = KeychainStore.serviceName(for: .officialServiceKey, signingChannel: "local")
    let store = KeychainStore.serviceName(for: .officialServiceKey, signingChannel: "app-store")

    #expect(local != store)
    #expect(local.contains("official-service.v2.local"))
    #expect(store.contains("official-service.v2.app-store"))
}

@Test func developmentCloudKeysDoNotTouchAppStoreKeychainItems() {
    let development = KeychainStore.serviceName(for: .cloudASRKey, signingChannel: "development")
    let appStore = KeychainStore.serviceName(for: .cloudASRKey, signingChannel: "app-store")

    #expect(development != appStore)
    #expect(development.contains("cloud-asr-key.v2.development"))
    #expect(appStore == "com.jago.subforge")
}

@Test func reconciledAppleTransactionsAreDeduplicatedAndBounded() throws {
    let suiteName = "SubForgeTests.apple-reconciliation.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    AppleTransactionReconciliationStore.markReconciled("100", defaults: defaults)
    AppleTransactionReconciliationStore.markReconciled("100", defaults: defaults)
    AppleTransactionReconciliationStore.markReconciled("101", defaults: defaults)

    #expect(AppleTransactionReconciliationStore.reconciledIDs(defaults: defaults) == ["100", "101"])
}

@MainActor
@Test func appTransactionRefreshesWhenSharedValueIsUnavailable() async throws {
    enum ExpectedFailure: Error { case unavailable }
    var sharedCalls = 0
    var refreshCalls = 0
    var observedFailure = false

    let value: String = try await SmartServiceStore.loadWithRefreshFallback(
        shared: {
            sharedCalls += 1
            throw ExpectedFailure.unavailable
        },
        refresh: {
            refreshCalls += 1
            return "signed-app-transaction"
        },
        onSharedFailure: { _ in observedFailure = true }
    )

    #expect(value == "signed-app-transaction")
    #expect(sharedCalls == 1)
    #expect(refreshCalls == 1)
    #expect(observedFailure)
}
