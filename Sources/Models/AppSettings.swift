import Foundation

struct SettingsValidationState: Equatable, Codable {
    var hasValidated = false
    var passed = false
    var resultText = "还没有执行验证"

    var statusText: String {
        if !hasValidated { return "未验证" }
        return passed ? "验证通过" : "验证失败"
    }

    var statusIcon: String {
        if !hasValidated { return "clock" }
        return passed ? "checkmark.circle.fill" : "xmark.circle.fill"
    }
}

struct AppSettings: Equatable, Codable {
    var interfaceLanguage: InterfaceLanguage = .simplifiedChinese
    var showMenuBarIcon = true

    /// 新安装默认官方智能字幕；已有用户配置不因升级被强制改写。
    var transcriptionEngine: TranscriptionEngine = .officialSmart
    var whisperModel: WhisperModel = .base
    var cloudASRPreset: CloudASRPreset = .dashscope
    var cloudASRURL: String = CloudASRPreset.dashscope.defaultURL
    var cloudASRKey: String = ""
    var cloudASRModel: String = CloudASRPreset.dashscope.defaultModel
    var language: String = "zh-CN"
    var sentenceSplitStrategy: SentenceSplitStrategy = .punctuation
    /// 旧版公共设置，保留用于迁移未分方案的历史配置。
    var maxSubtitleLength: Int? = 24
    var officialMaxSubtitleLength: Int?
    var customMaxSubtitleLength: Int?
    var localMaxSubtitleLength: Int?
    var keepFillerWords = false
    var transcriptionValidationState = SettingsValidationState()
    var customTranscriptionValidationState = SettingsValidationState()
    var localTranscriptionValidationState = SettingsValidationState()

    var proofreadingEnabled = false
    var proofreadingEngine: ProofreadingEngine = .cloudLLM
    var cloudLLMPreset: CloudLLMPreset = .deepseek
    var cloudLLMURL: String = CloudLLMPreset.deepseek.defaultURL
    var cloudLLMKey: String = ""
    var cloudLLMModel: String = CloudLLMPreset.deepseek.defaultModel
    var proofreadingPrompt = "只修正错别字、标点和明显断句问题，不改写说话人的语气。字幕行末不补句号、逗号、顿号、分号或冒号；问号、叹号、省略号只有表达语气时才保留。"
    var proofreadingStrictCorrections = true
    var proofreadingValidationState = SettingsValidationState()

    var subtitleStyle = SubtitleStyle()
    var exportSettings = ExportSettings()
    var watchSettings = WatchSettings()

    var effectiveASRURL: String {
        let trimmed = cloudASRURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? cloudASRPreset.defaultURL : trimmed
    }

    var effectiveASRModel: String {
        let trimmed = cloudASRModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? cloudASRPreset.defaultModel : trimmed
    }

    var activeTranscriptionValidationState: SettingsValidationState {
        transcriptionValidationState(for: transcriptionEngine)
    }

    func transcriptionValidationState(for engine: TranscriptionEngine) -> SettingsValidationState {
        switch engine {
        case .cloudASR:
            return customTranscriptionValidationState
        case .funASRLocal, .whisperLocal, .appleSpeech:
            return localTranscriptionValidationState
        case .officialSmart:
            return transcriptionValidationState
        }
    }

    mutating func setActiveTranscriptionValidationState(_ state: SettingsValidationState) {
        setTranscriptionValidationState(state, for: transcriptionEngine)
    }

    mutating func setTranscriptionValidationState(
        _ newState: SettingsValidationState,
        for engine: TranscriptionEngine
    ) {
        switch engine {
        case .cloudASR:
            customTranscriptionValidationState = newState
        case .funASRLocal, .whisperLocal, .appleSpeech:
            localTranscriptionValidationState = newState
        case .officialSmart:
            transcriptionValidationState = newState
        }
    }

    var effectiveMaxSubtitleLength: Int {
        effectiveMaxSubtitleLength(for: subtitleLengthProfile)
    }

    var subtitleLengthProfile: SubtitleLengthProfile {
        switch transcriptionEngine {
        case .officialSmart:
            .official
        case .cloudASR:
            .custom
        case .funASRLocal, .whisperLocal, .appleSpeech:
            .local
        }
    }

    func effectiveMaxSubtitleLength(for profile: SubtitleLengthProfile) -> Int {
        let configured: Int?
        switch profile {
        case .official:
            configured = officialMaxSubtitleLength
        case .custom:
            configured = customMaxSubtitleLength
        case .local:
            configured = localMaxSubtitleLength
        }
        return Self.clampSubtitleLength(configured ?? maxSubtitleLength ?? 24)
    }

    mutating func setMaxSubtitleLength(_ value: Int, for profile: SubtitleLengthProfile) {
        let clamped = Self.clampSubtitleLength(value)
        switch profile {
        case .official:
            officialMaxSubtitleLength = clamped
        case .custom:
            customMaxSubtitleLength = clamped
        case .local:
            localMaxSubtitleLength = clamped
        }
    }

    private static func clampSubtitleLength(_ value: Int) -> Int {
        min(max(value, 10), 50)
    }

    var effectiveLLMURL: String {
        cloudLLMURL.isEmpty ? cloudLLMPreset.defaultURL : cloudLLMURL
    }

    var effectiveLLMModel: String {
        cloudLLMModel.isEmpty ? cloudLLMPreset.defaultModel : cloudLLMModel
    }

    /// AI 校对开关打开且云端 URL / Key / 模型齐全。
    var isProofreadingFullyConfigured: Bool {
        guard proofreadingEnabled else { return false }
        let key = cloudLLMKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = effectiveLLMURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = effectiveLLMModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return !key.isEmpty && !url.isEmpty && !model.isEmpty
    }

    /// 开关开了但缺配置时的说明；配置齐全或未开启则 nil。
    var proofreadingConfigWarning: String? {
        guard proofreadingEnabled else { return nil }
        if isProofreadingFullyConfigured { return nil }
        let key = cloudLLMKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            return "已开启 AI 校对，但未填写 API Key"
        }
        if effectiveLLMURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "已开启 AI 校对，但未填写 Base URL"
        }
        if effectiveLLMModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "已开启 AI 校对，但未填写模型名"
        }
        return "已开启 AI 校对，但配置不完整"
    }
}

enum SubtitleLengthProfile {
    case official
    case custom
    case local
}

enum InterfaceLanguage: String, CaseIterable, Codable, Identifiable {
    case simplifiedChinese = "简体中文"
    case english = "English"

    var id: String { rawValue }
}

enum SentenceSplitStrategy: String, CaseIterable, Codable, Identifiable {
    case punctuation = "按标点"
    case duration = "按时长"

    var id: String { rawValue }
}
