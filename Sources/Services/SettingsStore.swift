import Foundation

enum SettingsStore {
    private static let key = "subforge.settings.v2"

    static func load() -> AppSettings {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            var settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return AppSettings()
        }

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

        return settings
    }

    static func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
