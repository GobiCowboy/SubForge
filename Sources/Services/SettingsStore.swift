import Foundation

enum SettingsStore {
    private static let key = "subforge.settings.v2"
    private static let isKeychainPersistenceEnabled = true

    static func load() -> AppSettings {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            var settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return AppSettings()
        }

        normalize(&settings)

        if isKeychainPersistenceEnabled {
            let hadPlaintextASRKey = !settings.cloudASRKey.isEmpty
            let hadPlaintextLLMKey = !settings.cloudLLMKey.isEmpty

            if hadPlaintextASRKey {
                KeychainStore.save(settings.cloudASRKey, account: .cloudASRKey)
            }

            if hadPlaintextLLMKey {
                KeychainStore.save(settings.cloudLLMKey, account: .cloudLLMKey)
            }

            if hadPlaintextASRKey || hadPlaintextLLMKey {
                persistPreferences(settings, includeSecrets: false)
                settings.cloudASRKey = ""
                settings.cloudLLMKey = ""
            }
        }

        return settings
    }

    static func save(_ settings: AppSettings) {
        if isKeychainPersistenceEnabled {
            saveNonEmptySecrets(settings)
            persistPreferences(settings, includeSecrets: false)
        } else {
            persistPreferences(settings, includeSecrets: true)
        }
    }

    static func hydrateSecrets(into settings: inout AppSettings, includeASR: Bool = true, includeLLM: Bool = true) {
        guard isKeychainPersistenceEnabled else { return }

        if includeASR, settings.cloudASRKey.isEmpty {
            settings.cloudASRKey = KeychainStore.read(.cloudASRKey) ?? ""
        }

        if includeLLM, settings.cloudLLMKey.isEmpty {
            settings.cloudLLMKey = KeychainStore.read(.cloudLLMKey) ?? ""
        }
    }

    static func deleteASRKey() {
        guard isKeychainPersistenceEnabled else { return }
        KeychainStore.delete(.cloudASRKey)
    }

    static func deleteLLMKey() {
        guard isKeychainPersistenceEnabled else { return }
        KeychainStore.delete(.cloudLLMKey)
    }

    private static func normalize(_ settings: inout AppSettings) {
        if settings.proofreadingEngine == .appleLocal {
            settings.proofreadingEngine = .cloudLLM
        }

        if settings.cloudASRURL.isEmpty, settings.cloudASRPreset != .custom {
            settings.cloudASRURL = settings.cloudASRPreset.defaultURL
        }

        if settings.cloudASRModel.isEmpty, settings.cloudASRPreset != .custom {
            settings.cloudASRModel = settings.cloudASRPreset.defaultModel
        }

        if settings.cloudLLMURL.isEmpty, settings.cloudLLMPreset != .custom {
            settings.cloudLLMURL = settings.cloudLLMPreset.defaultURL
        }

        if settings.cloudLLMModel.isEmpty, settings.cloudLLMPreset != .custom {
            settings.cloudLLMModel = settings.cloudLLMPreset.defaultModel
        } else if settings.cloudLLMPreset == .deepseek, settings.cloudLLMModel == "deepseek-chat" {
            settings.cloudLLMModel = CloudLLMPreset.deepseek.defaultModel
        }

        if !WhisperModelStore.isAvailable(settings.whisperModel),
           let firstAvailableModel = WhisperModelStore.availableModels().first {
            settings.whisperModel = firstAvailableModel
        }
    }

    private static func persistPreferences(_ settings: AppSettings, includeSecrets: Bool) {
        var persisted = settings
        if !includeSecrets {
            persisted.cloudASRKey = ""
            persisted.cloudLLMKey = ""
        }
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func saveNonEmptySecrets(_ settings: AppSettings) {
        if !settings.cloudASRKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            KeychainStore.save(settings.cloudASRKey, account: .cloudASRKey)
        }

        if !settings.cloudLLMKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            KeychainStore.save(settings.cloudLLMKey, account: .cloudLLMKey)
        }
    }
}
