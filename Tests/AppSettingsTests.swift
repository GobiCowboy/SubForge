import Foundation
import Testing
@testable import SubForge

@Test func subtitleLengthSettingIsSharedByEveryPlan() {
    var settings = AppSettings()
    settings.maxSubtitleLength = 38

    settings.transcriptionEngine = .officialSmart
    #expect(settings.effectiveMaxSubtitleLength == 38)

    settings.transcriptionEngine = .cloudASR
    #expect(settings.effectiveMaxSubtitleLength == 38)

    settings.transcriptionEngine = .funASRLocal
    #expect(settings.effectiveMaxSubtitleLength == 38)
}

@Test func subtitleRulesMigrationForces32OnlyOnce() {
    var legacy = AppSettings()
    legacy.maxSubtitleLength = 40
    legacy.subtitleRulesRevision = nil
    legacy.proofreadingPrompt = AppSettings.legacyProofreadingPrompt

    #expect(SettingsStore.normalize(&legacy))
    #expect(legacy.maxSubtitleLength == 32)
    #expect(legacy.subtitleRulesRevision == AppSettings.currentSubtitleRulesRevision)
    #expect(legacy.proofreadingPrompt == AppSettings.defaultProofreadingPrompt)

    legacy.maxSubtitleLength = 24
    #expect(!SettingsStore.normalize(&legacy))
    #expect(legacy.maxSubtitleLength == 24)
}

@Test func settingsDecodeWhenNewSubtitleFieldsAreMissing() throws {
    let encoded = try JSONEncoder().encode(AppSettings())
    var json = try #require(
        JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    json.removeValue(forKey: "subtitleRulesRevision")
    json.removeValue(forKey: "retainedSubtitlePunctuation")
    json.removeValue(forKey: "hotwordPromptPreference")
    json.removeValue(forKey: "fixedHotwordsEnabled")
    json.removeValue(forKey: "fixedHotwordsText")

    let legacyData = try JSONSerialization.data(withJSONObject: json)
    var decoded = try JSONDecoder().decode(AppSettings.self, from: legacyData)

    #expect(decoded.subtitleRulesRevision == nil)
    #expect(decoded.effectiveRetainedSubtitlePunctuation == SubtitlePunctuationGroup.subtitleRecommended)
    #expect(decoded.effectiveHotwordPromptPreference == .undecided)
    #expect(!decoded.effectiveFixedHotwordsEnabled)
    #expect(decoded.effectiveFixedHotwordsText.isEmpty)
    #expect(SettingsStore.normalize(&decoded))
    #expect(decoded.maxSubtitleLength == 32)
}

@Test func newSettingsUseRecommendedSubtitlePunctuation() {
    let settings = AppSettings()

    #expect(
        settings.effectiveRetainedSubtitlePunctuation
            == SubtitlePunctuationGroup.subtitleRecommended
    )
}

@Test func defaultExportSettingsMatchFinalCutWorkflow() {
    let settings = ExportSettings()

    #expect(settings.format == .srtAndFCPXML)
    #expect(settings.exportToFinalCutPro)
    #expect(settings.saveLocation == .sameAsSource)
    #expect(settings.overwriteExisting)
}

@Test func missingExportPreferencesUseNewDefaults() throws {
    let settings = try JSONDecoder().decode(ExportSettings.self, from: Data("{}".utf8))

    #expect(settings.exportToFinalCutPro)
    #expect(settings.overwriteExisting)
    #expect(settings.sourceOutputPath.isEmpty)
    #expect(settings.sourceOutputBookmarkData == nil)
}

@Test func sourceExportDirectoryAuthorizationPersists() throws {
    var settings = ExportSettings()
    settings.sourceOutputPath = "/tmp/video-project"
    settings.sourceOutputBookmarkData = Data([1, 2, 3])

    let data = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(ExportSettings.self, from: data)

    #expect(decoded.sourceOutputPath == settings.sourceOutputPath)
    #expect(decoded.sourceOutputBookmarkData == settings.sourceOutputBookmarkData)
}

@Test func subtitlePlanGroupsTranscriptionEngines() {
    #expect(SubtitlePlan(engine: .officialSmart) == .official)
    #expect(SubtitlePlan(engine: .cloudASR) == .custom)
    #expect(SubtitlePlan(engine: .funASRLocal) == .local)
    #expect(SubtitlePlan(engine: .whisperLocal) == .local)
    #expect(SubtitlePlan(engine: .appleSpeech) == .local)
}

@Test func transcriptionEngineIdentifiesLocalProcessing() {
    #expect(TranscriptionEngine.funASRLocal.isLocal)
    #expect(TranscriptionEngine.whisperLocal.isLocal)
    #expect(TranscriptionEngine.appleSpeech.isLocal)
    #expect(!TranscriptionEngine.cloudASR.isLocal)
    #expect(!TranscriptionEngine.officialSmart.isLocal)
}

@Test func transcriptionValidationStateIsIndependentByPlan() {
    var settings = AppSettings()
    let customState = SettingsValidationState(hasValidated: true, passed: true, resultText: "custom ok")
    let localState = SettingsValidationState(hasValidated: true, passed: false, resultText: "local failed")

    settings.transcriptionEngine = .cloudASR
    settings.setActiveTranscriptionValidationState(customState)

    settings.transcriptionEngine = .funASRLocal
    settings.setActiveTranscriptionValidationState(localState)

    settings.transcriptionEngine = .cloudASR
    #expect(settings.activeTranscriptionValidationState.hasValidated)
    #expect(settings.activeTranscriptionValidationState.resultText == customState.resultText)

    settings.transcriptionEngine = .funASRLocal
    #expect(settings.activeTranscriptionValidationState.hasValidated)
    #expect(settings.activeTranscriptionValidationState.resultText == localState.resultText)
}

@Test func customValidationClearsOnlyWhenCustomFieldsChange() {
    var settings = AppSettings()
    let passed = SettingsValidationState(hasValidated: true, passed: true, resultText: "ok")
    settings.customTranscriptionValidationState = passed
    settings.localTranscriptionValidationState = passed

    settings.setCustomASRURL("https://example.com")

    #expect(!settings.customTranscriptionValidationState.hasValidated)
    #expect(settings.localTranscriptionValidationState.hasValidated)
}

@Test func customKeyHydrationDoesNotRestoreOrClearValidation() {
    var settings = AppSettings()
    settings.customTranscriptionValidationState = SettingsValidationState()

    settings.hydrateCustomASRKey("key-from-keychain")

    #expect(settings.cloudASRKey == "key-from-keychain")
    #expect(!settings.customTranscriptionValidationState.hasValidated)
}

@Test func localAndProofreadingValidationResetIndependently() {
    var settings = AppSettings()
    let passed = SettingsValidationState(hasValidated: true, passed: true, resultText: "ok")
    settings.customTranscriptionValidationState = passed
    settings.localTranscriptionValidationState = passed
    settings.proofreadingValidationState = passed

    settings.setLocalWhisperModel(.small)
    #expect(settings.customTranscriptionValidationState.hasValidated)
    #expect(!settings.localTranscriptionValidationState.hasValidated)
    #expect(settings.proofreadingValidationState.hasValidated)

    settings.setProofreadingModel("another-model")
    #expect(settings.customTranscriptionValidationState.hasValidated)
    #expect(!settings.proofreadingValidationState.hasValidated)
}

@Test func workflowAllowsUnverifiedAndBlocksOnlyExplicitFailure() {
    var settings = AppSettings()
    settings.transcriptionEngine = .cloudASR
    settings.proofreadingEnabled = true

    #expect(settings.allowsTranscriptionAfterValidation)
    #expect(settings.shouldRunProofreading)

    settings.customTranscriptionValidationState = SettingsValidationState(
        hasValidated: true,
        passed: false,
        resultText: "failed"
    )
    settings.proofreadingValidationState = SettingsValidationState(
        hasValidated: true,
        passed: false,
        resultText: "failed"
    )

    #expect(!settings.allowsTranscriptionAfterValidation)
    #expect(!settings.shouldRunProofreading)

    settings.customTranscriptionValidationState.passed = true
    settings.proofreadingValidationState.passed = true
    #expect(settings.allowsTranscriptionAfterValidation)
    #expect(settings.shouldRunProofreading)
}
