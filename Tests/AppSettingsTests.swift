import Foundation
import Testing
@testable import SubForge

@Test func subtitleLengthSettingsAreIndependentByPlan() {
    var settings = AppSettings()
    settings.officialMaxSubtitleLength = 12
    settings.customMaxSubtitleLength = 20
    settings.localMaxSubtitleLength = 30

    settings.transcriptionEngine = .officialSmart
    #expect(settings.effectiveMaxSubtitleLength == 12)

    settings.transcriptionEngine = .cloudASR
    #expect(settings.effectiveMaxSubtitleLength == 20)

    settings.transcriptionEngine = .funASRLocal
    #expect(settings.effectiveMaxSubtitleLength == 30)
}

@Test func legacySubtitleLengthSeedsEveryPlan() throws {
    var legacy = AppSettings()
    legacy.maxSubtitleLength = 18

    let data = try JSONEncoder().encode(legacy)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

    #expect(decoded.effectiveMaxSubtitleLength(for: .official) == 18)
    #expect(decoded.effectiveMaxSubtitleLength(for: .custom) == 18)
    #expect(decoded.effectiveMaxSubtitleLength(for: .local) == 18)
}
