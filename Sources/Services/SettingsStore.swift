import Foundation

enum SettingsStore {
    private static let key = "subforge.settings.v2"
    private static let isKeychainPersistenceEnabled = false

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
            migratePlaintextKeyIfNeeded(settings.cloudASRKey, account: .cloudASRKey)
            migratePlaintextKeyIfNeeded(settings.cloudLLMKey, account: .cloudLLMKey)
            settings.cloudASRKey = KeychainStore.read(.cloudASRKey) ?? settings.cloudASRKey
            settings.cloudLLMKey = KeychainStore.read(.cloudLLMKey) ?? settings.cloudLLMKey

            if hadPlaintextASRKey || hadPlaintextLLMKey {
                persistPreferences(settings, includeSecrets: false)
            }
        }

        return settings
    }

    static func save(_ settings: AppSettings) {
        if isKeychainPersistenceEnabled {
            KeychainStore.save(settings.cloudASRKey, account: .cloudASRKey)
            KeychainStore.save(settings.cloudLLMKey, account: .cloudLLMKey)
            persistPreferences(settings, includeSecrets: false)
        } else {
            persistPreferences(settings, includeSecrets: true)
        }
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

    private static func migratePlaintextKeyIfNeeded(_ value: String, account: KeychainStore.Account) {
        if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           KeychainStore.read(account) == nil {
            KeychainStore.save(value, account: account)
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
}
