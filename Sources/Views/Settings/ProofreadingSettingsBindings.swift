import SwiftUI

extension ProofreadingSettingsPane {
    var proofreadingEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.proofreadingEnabled },
            set: {
                cancelValidation()
                settings.setProofreadingEnabled($0)
            }
        )
    }

    var proofreadingPresetBinding: Binding<CloudLLMPreset> {
        Binding(
            get: { settings.cloudLLMPreset },
            set: {
                cancelValidation()
                settings.setProofreadingPreset($0)
            }
        )
    }

    var proofreadingURLBinding: Binding<String> {
        Binding(
            get: { settings.cloudLLMURL },
            set: {
                cancelValidation()
                settings.setProofreadingURL($0)
            }
        )
    }

    var proofreadingKeyBinding: Binding<String> {
        Binding(
            get: { settings.cloudLLMKey },
            set: {
                cancelValidation()
                if !settings.cloudLLMKey.isEmpty,
                   $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    SettingsStore.deleteLLMKey()
                }
                settings.setProofreadingKey($0)
            }
        )
    }

    var proofreadingModelBinding: Binding<String> {
        Binding(
            get: { settings.cloudLLMModel },
            set: {
                cancelValidation()
                settings.setProofreadingModel($0)
            }
        )
    }

    var proofreadingPromptBinding: Binding<String> {
        Binding(
            get: { settings.proofreadingPrompt },
            set: {
                cancelValidation()
                settings.setProofreadingPrompt($0)
            }
        )
    }
}
