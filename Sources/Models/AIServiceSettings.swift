import Foundation

enum TranscriptionEngine: String, CaseIterable, Codable, Identifiable {
    case whisperLocal = "本地 Whisper"
    case appleSpeech = "Apple 语音"
    case cloudASR = "云端 ASR"

    var id: String { rawValue }
}

enum WhisperModel: String, CaseIterable, Identifiable, Codable {
    case tiny = "tiny"
    case base = "base"
    case small = "small"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tiny:
            "Tiny (74MB)"
        case .base:
            "Base (142MB)"
        case .small:
            "Small (466MB)"
        }
    }

    var detail: String {
        switch self {
        case .tiny:
            "速度快，适合快速验证"
        case .base:
            "速度与质量更平衡"
        case .small:
            "质量更好，适合正式使用"
        }
    }

    var fileName: String {
        "ggml-\(rawValue).bin"
    }

    var sizeMB: Int {
        switch self {
        case .tiny: 74
        case .base: 142
        case .small: 466
        }
    }
}

enum WhisperModelStore {
    static let directory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("SubForge/models")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    static func localPath(for model: WhisperModel) -> URL {
        directory.appendingPathComponent(model.fileName)
    }

    static func bundledDevelopmentPath(for model: WhisperModel) -> URL {
        Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("BAK/models/\(model.fileName)")
    }

    static func existingPath(for model: WhisperModel) -> URL? {
        let candidates = [
            localPath(for: model),
            bundledDevelopmentPath(for: model)
        ]

        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func isAvailable(_ model: WhisperModel) -> Bool {
        existingPath(for: model) != nil
    }

    static func availableModels() -> [WhisperModel] {
        WhisperModel.allCases.filter(isAvailable)
    }
}

enum CloudASRPreset: String, CaseIterable, Codable, Identifiable {
    case dashscope = "阿里 DashScope"
    case siliconFlow = "硅基流动"
    case custom = "自定义"

    var id: String { rawValue }

    var defaultURL: String {
        switch self {
        case .dashscope:
            "https://{WorkspaceId}.cn-beijing.maas.aliyuncs.com/api/v1/services/audio/asr/transcription"
        case .siliconFlow:
            "https://api.siliconflow.cn/v1/audio/transcriptions"
        case .custom:
            ""
        }
    }

    var defaultModel: String {
        switch self {
        case .dashscope:
            "qwen3-asr-flash-filetrans"
        case .siliconFlow:
            "FunAudioLLM/SenseVoiceSmall"
        case .custom:
            ""
        }
    }
}

enum ProofreadingEngine: String, CaseIterable, Codable, Identifiable {
    case cloudLLM = "模型纠正"
    case appleLocal = "Apple 本地"

    var id: String { rawValue }
}

enum CloudLLMPreset: String, CaseIterable, Codable, Identifiable {
    case deepseek = "DeepSeek"
    case siliconFlow = "硅基流动"
    case openRouter = "OpenRouter"
    case custom = "自定义"

    var id: String { rawValue }

    var defaultURL: String {
        switch self {
        case .deepseek:
            "https://api.deepseek.com/v1/chat/completions"
        case .siliconFlow:
            "https://api.siliconflow.cn/v1/chat/completions"
        case .openRouter:
            "https://openrouter.ai/api/v1/chat/completions"
        case .custom:
            ""
        }
    }

    var defaultModel: String {
        switch self {
        case .deepseek:
            "deepseek-v4-flash"
        case .siliconFlow:
            "Qwen/Qwen2.5-7B-Instruct"
        case .openRouter:
            "openai/gpt-4o-mini"
        case .custom:
            ""
        }
    }
}
