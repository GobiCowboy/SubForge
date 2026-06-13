import Foundation

/// 导出设置
struct ExportSettings: Equatable, Codable {
    var fps: Int = 30
    var width: Int = 1920
    var height: Int = 1080
    var saveLocation: SaveLocation = .sameAsAudio
    var customOutputPath: String = ""
}

enum SaveLocation: String, CaseIterable, Codable {
    case sameAsAudio = "与音频同目录"
    case custom = "自定义目录"
}

// MARK: - 云端 ASR 预设

enum CloudASRPreset: String, CaseIterable, Codable {
    case dashscope = "阿里 DashScope"
    case custom = "自定义"

    var defaultURL: String {
        switch self {
        case .dashscope: return "https://dashscope.aliyuncs.com/api/v1/services/audio/asr/transcription"
        case .custom: return ""
        }
    }

    var defaultModel: String {
        switch self {
        case .dashscope: return "qwen3-asr-flash-filetrans"
        case .custom: return ""
        }
    }
}

// MARK: - 云端 LLM 预设

enum CloudLLMPreset: String, CaseIterable, Codable {
    case deepseek = "DeepSeek"
    case siliconflow = "硅基流动"
    case openrouter = "OpenRouter"
    case custom = "自定义"

    var defaultURL: String {
        switch self {
        case .deepseek: return "https://api.deepseek.com/v1/chat/completions"
        case .siliconflow: return "https://api.siliconflow.cn/v1/chat/completions"
        case .openrouter: return "https://openrouter.ai/api/v1/chat/completions"
        case .custom: return ""
        }
    }

    var defaultModel: String {
        switch self {
        case .deepseek: return "deepseek-chat"
        case .siliconflow: return "Qwen/Qwen2.5-7B-Instruct"
        case .openrouter: return "openai/gpt-4o-mini"
        case .custom: return ""
        }
    }
}

// MARK: - AppSettings（合并所有设置）

struct AppSettings: Equatable, Codable {
    // 转写
    var transcriptionEngine: TranscriptionEngine = .appleSpeech
    var language: String = "zh-CN"

    // AI 校对
    var proofreadingEnabled: Bool = false
    var proofreadingEngine: ProofreadingEngine = .appleLocal

    // 字幕样式
    var subtitleStyle = SubtitleStyle()

    // 字幕处理
    var maxSubtitleLength: Int = 20  // 每条字幕最大字符数，0=不限制

    // 输出
    var exportSettings = ExportSettings()

    // 云端 ASR
    var cloudASRPreset: CloudASRPreset = .dashscope
    var cloudASRURL: String = ""
    var cloudASRKey: String = ""
    var cloudASRModel: String = ""

    // 云端 LLM
    var cloudLLMPreset: CloudLLMPreset = .deepseek
    var cloudLLMURL: String = ""
    var cloudLLMKey: String = ""
    var cloudLLMModel: String = ""

    /// 获取实际 ASR URL（预设值优先）
    var effectiveASRURL: String {
        cloudASRURL.isEmpty ? cloudASRPreset.defaultURL : cloudASRURL
    }
    var effectiveASRModel: String {
        cloudASRModel.isEmpty ? cloudASRPreset.defaultModel : cloudASRModel
    }
    var effectiveLLMURL: String {
        cloudLLMURL.isEmpty ? cloudLLMPreset.defaultURL : cloudLLMURL
    }
    var effectiveLLMModel: String {
        cloudLLMModel.isEmpty ? cloudLLMPreset.defaultModel : cloudLLMModel
    }
}

enum TranscriptionEngine: String, CaseIterable, Codable {
    case appleSpeech = "Apple Speech"
    case cloudASR = "云端 ASR API"
}

enum ProofreadingEngine: String, CaseIterable, Codable {
    case appleLocal = "Apple 本地"
    case cloudLLM = "云端 LLM API"
}
