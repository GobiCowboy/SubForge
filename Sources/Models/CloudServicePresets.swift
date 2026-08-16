import Foundation

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
