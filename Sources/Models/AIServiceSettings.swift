import Foundation

enum TranscriptionEngine: String, CaseIterable, Codable, Identifiable {
    case whisperLocal = "本地 Whisper"
    case funASRLocal = "本地 FunASR"
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

    static func bundledResourcePath(for model: WhisperModel) -> URL {
        Bundle.main.resourceURL?.appendingPathComponent(model.fileName)
            ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(model.fileName)")
    }

    static func isBundled(_ model: WhisperModel) -> Bool {
        FileManager.default.fileExists(atPath: bundledResourcePath(for: model).path)
    }

    static func existingPath(for model: WhisperModel) -> URL? {
        let candidates = [
            localPath(for: model),
            bundledResourcePath(for: model),
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

/// SenseVoice GGUF 模型（一期仅 q8）。
enum FunASRModel: String, CaseIterable, Identifiable, Codable {
    case sensevoiceSmallQ8 = "sensevoice-small-q8"

    var id: String { rawValue }

    var displayName: String {
        "SenseVoice Small q8 (~254MB)"
    }

    var detail: String {
        "中日韩英多语本地识别；需同时下载 FSMN-VAD"
    }

    var fileName: String {
        "sensevoice-small-q8.gguf"
    }

    /// Hugging Face 仓库路径片段，用于拼接 resolve URL。
    var repository: String {
        "FunAudioLLM/SenseVoiceSmall-GGUF"
    }

    var sizeMB: Int { 254 }
}

enum FunASRModelStore {
    static let directory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("SubForge/models/funasr")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    static let vadFileName = "fsmn-vad.gguf"
    static let vadRepository = "FunAudioLLM/fsmn-vad-GGUF"
    static let vadSizeMB = 2

    static func localPath(for model: FunASRModel) -> URL {
        directory.appendingPathComponent(model.fileName)
    }

    static var vadPath: URL {
        directory.appendingPathComponent(vadFileName)
    }

    static func isModelAvailable(_ model: FunASRModel = .sensevoiceSmallQ8) -> Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: localPath(for: model).path)
        let size = attributes?[.size] as? Int64 ?? 0
        return size > 10_000_000
    }

    static var isVADAvailable: Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: vadPath.path)
        let size = attributes?[.size] as? Int64 ?? 0
        return size > 50_000
    }

    static func isReady(_ model: FunASRModel = .sensevoiceSmallQ8) -> Bool {
        isModelAvailable(model) && isVADAvailable
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
            // 与 Git 一致：异步 transcription 端点 + filetrans。
            // 使用官方仍支持的 dashscope 域名，避免 {WorkspaceId} 占位导致无法验证。
            // 若有业务空间专属域名，可在设置里改成：
            // https://{WorkspaceId}.cn-beijing.maas.aliyuncs.com/api/v1/services/audio/asr/transcription
            "https://dashscope.aliyuncs.com/api/v1/services/audio/asr/transcription"
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
