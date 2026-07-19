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
    #expect(OfficialServiceConfiguration.internalProductID == "subforge_smart_300")
    #expect(OfficialServiceConfiguration.appleProductID == "com.jago.subforge.smart.300min")
    #expect(OfficialPurchasePlan.starter.appleProductID == "com.jago.subforge.smart.60min")
    #expect(OfficialPurchasePlan.starter.internalProductID == "subforge_smart_60")
    #expect(OfficialPurchasePlan.starter.minutes == 60)
    #expect(OfficialPurchasePlan.standard.minutes == 300)
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
