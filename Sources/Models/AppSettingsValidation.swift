import Foundation

extension AppSettings {
    /// 验证是可选诊断：未验证或验证通过均可继续，只有明确失败才拦截。
    var allowsTranscriptionAfterValidation: Bool {
        if transcriptionEngine == .officialSmart {
            return true
        }
        let state = activeTranscriptionValidationState
        return !state.hasValidated || state.passed
    }

    var shouldRunProofreading: Bool {
        if transcriptionEngine == .officialSmart {
            return true
        }
        return proofreadingEnabled
            && (!proofreadingValidationState.hasValidated
                || proofreadingValidationState.passed)
    }

    mutating func setCustomASRPreset(_ value: CloudASRPreset) {
        guard cloudASRPreset != value else { return }
        customTranscriptionValidationState = SettingsValidationState()
        cloudASRPreset = value
        cloudASRURL = value.defaultURL
        cloudASRModel = value.defaultModel
    }

    mutating func setCustomASRURL(_ value: String) {
        guard cloudASRURL != value else { return }
        customTranscriptionValidationState = SettingsValidationState()
        cloudASRURL = value
    }

    mutating func setCustomASRKey(_ value: String) {
        guard cloudASRKey != value else { return }
        customTranscriptionValidationState = SettingsValidationState()
        cloudASRKey = value
    }

    mutating func hydrateCustomASRKey(_ value: String) {
        cloudASRKey = value
    }

    mutating func setCustomASRModel(_ value: String) {
        guard cloudASRModel != value else { return }
        customTranscriptionValidationState = SettingsValidationState()
        cloudASRModel = value
    }

    mutating func setTranscriptionLanguage(_ value: String) {
        guard language != value else { return }
        customTranscriptionValidationState = SettingsValidationState()
        localTranscriptionValidationState = SettingsValidationState()
        language = value
    }

    mutating func setLocalTranscriptionEngine(_ value: TranscriptionEngine) {
        guard transcriptionEngine != value else { return }
        localTranscriptionValidationState = SettingsValidationState()
        transcriptionEngine = value
    }

    mutating func setLocalWhisperModel(_ value: WhisperModel) {
        guard whisperModel != value else { return }
        localTranscriptionValidationState = SettingsValidationState()
        whisperModel = value
    }

    mutating func setProofreadingEnabled(_ value: Bool) {
        guard proofreadingEnabled != value else { return }
        proofreadingValidationState = SettingsValidationState()
        proofreadingEnabled = value
    }

    mutating func setProofreadingPreset(_ value: CloudLLMPreset) {
        guard cloudLLMPreset != value else { return }
        proofreadingValidationState = SettingsValidationState()
        cloudLLMPreset = value
        cloudLLMURL = value.defaultURL
        cloudLLMModel = value.defaultModel
        proofreadingEngine = .cloudLLM
    }

    mutating func setProofreadingURL(_ value: String) {
        guard cloudLLMURL != value else { return }
        proofreadingValidationState = SettingsValidationState()
        cloudLLMURL = value
    }

    mutating func setProofreadingKey(_ value: String) {
        guard cloudLLMKey != value else { return }
        proofreadingValidationState = SettingsValidationState()
        cloudLLMKey = value
    }

    mutating func hydrateProofreadingKey(_ value: String) {
        cloudLLMKey = value
    }

    mutating func setProofreadingModel(_ value: String) {
        guard cloudLLMModel != value else { return }
        proofreadingValidationState = SettingsValidationState()
        cloudLLMModel = value
    }

    mutating func setProofreadingPrompt(_ value: String) {
        guard proofreadingPrompt != value else { return }
        proofreadingValidationState = SettingsValidationState()
        proofreadingPrompt = value
    }
}
