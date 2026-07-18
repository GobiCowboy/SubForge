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
}
