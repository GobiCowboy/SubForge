import Foundation

enum TranscriptionEngine: String, CaseIterable, Codable, Identifiable {
    /// 推荐本地听写（中日韩）；时间轴为估算。
    case funASRLocal = "本地 FunASR"
    /// 备选；模型不内置，设置中下载。
    case whisperLocal = "本地 Whisper"
    case appleSpeech = "Apple 语音"
    /// 官方付费能力：中国区云端ASR + AI校对。
    case officialSmart = "智能字幕"
    /// 用户自备Key的专家入口。
    case cloudASR = "云端 ASR"

    var id: String { rawValue }
}

enum OfficialServiceRegion: String, CaseIterable, Codable, Identifiable {
    case china
    case international

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .china: "中国大陆"
        case .international: "国际"
        }
    }
}

enum OfficialPurchasePlan: String, CaseIterable, Codable, Hashable, Identifiable {
    case starter
    case standard

    var id: String { rawValue }

    var minutes: Int {
        switch self {
        case .starter: 60
        case .standard: 300
        }
    }

    var title: String {
        "\(minutes) 分钟"
    }

    var badge: String {
        switch self {
        case .starter: "轻量尝试"
        case .standard: "常用套餐 · 推荐"
        }
    }

    var appleProductID: String {
        switch self {
        case .starter: "com.jago.subforge.smart.60min"
        case .standard: "com.jago.subforge.smart.300min"
        }
    }

    var internalProductID: String {
        switch self {
        case .starter: "subforge_smart_60"
        case .standard: "subforge_smart_300"
        }
    }
}

struct OfficialServiceProfile: Equatable {
    let region: OfficialServiceRegion
    let billingBaseURL: URL
    let modelBaseURL: URL
    let processingRegion: String
}

enum OfficialServiceConfiguration {
    static let applicationID = "subforge"
    static let activeRegion: OfficialServiceRegion = .china
    static let purchasePlans = OfficialPurchasePlan.allCases
    static let appleProductID = OfficialPurchasePlan.standard.appleProductID
    static let internalProductID = OfficialPurchasePlan.standard.internalProductID

    static func purchaseOrderBody(
        plan: OfficialPurchasePlan,
        existingKey: String?
    ) -> [String: String] {
        var body = [
            "applicationId": applicationID,
            "productId": plan.internalProductID
        ]
        if let existingKey, !existingKey.isEmpty {
            body["existingApiKey"] = existingKey
        }
        return body
    }

    static func profile(for region: OfficialServiceRegion) -> OfficialServiceProfile? {
        switch region {
        case .china:
            return OfficialServiceProfile(
                region: .china,
                billingBaseURL: URL(string: "https://billing.gobicowboy.cn")!,
                modelBaseURL: URL(string: "https://model-api.gobicowboy.cn/v1")!,
                processingRegion: "china"
            )
        case .international:
            // 保留区域类型，中国区验证完成前不配置Base URL，也不自动跨区。
            return nil
        }
    }

    static var activeProfile: OfficialServiceProfile {
        guard let profile = profile(for: activeRegion) else {
            preconditionFailure("Official service region is not configured")
        }
        return profile
    }
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
    /// App 沙箱内目录（正式读写位置）。调试包若开启 sandbox，也会落到 Containers 下。
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

    /// 安装包内置模型目录（`Contents/Resources/funasr/`）。
    static var bundledResourceDirectory: URL {
        Bundle.main.resourceURL?.appendingPathComponent("funasr")
            ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/funasr")
    }

    /// FileAttributeKey.size 在运行时是 NSNumber，直接 `as? Int64` 会失败并误判为「未下载」。
    private static func fileSize(at url: URL) -> Int64 {
        guard let value = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] else {
            return 0
        }
        if let number = value as? NSNumber {
            return number.int64Value
        }
        if let int64 = value as? Int64 {
            return int64
        }
        if let uint64 = value as? UInt64 {
            return Int64(uint64)
        }
        if let int = value as? Int {
            return Int64(int)
        }
        return 0
    }

    static func isBundled(_ model: FunASRModel = .sensevoiceSmallQ8) -> Bool {
        let asr = bundledResourceDirectory.appendingPathComponent(model.fileName)
        let vad = bundledResourceDirectory.appendingPathComponent(vadFileName)
        return fileSize(at: asr) > 10_000_000 && fileSize(at: vad) > 50_000
    }

    /// 兼容：优先包内 Resources，再沙箱 Application Support、开发机路径。
    private static func candidateDirectories() -> [URL] {
        var dirs: [URL] = [
            bundledResourceDirectory,
            directory
        ]
        let home = FileManager.default.homeDirectoryForCurrentUser
        dirs.append(
            home
                .appendingPathComponent("Library/Application Support/SubForge/models/funasr")
        )
        dirs.append(
            Bundle.main.bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("vendor/funasr")
        )
        var seen = Set<String>()
        return dirs.filter { url in
            let path = url.standardizedFileURL.path
            if seen.contains(path) { return false }
            seen.insert(path)
            return true
        }
    }

    static func existingPath(for fileName: String, minimumBytes: Int64) -> URL? {
        for dir in candidateDirectories() {
            let url = dir.appendingPathComponent(fileName)
            if fileSize(at: url) > minimumBytes {
                return url
            }
        }
        return nil
    }

    static func resolveModelPath(_ model: FunASRModel = .sensevoiceSmallQ8) -> URL? {
        if let found = existingPath(for: model.fileName, minimumBytes: 10_000_000) {
            // 包内 Resources 可直接读，不必先拷 242MB 进沙箱（VM 磁盘/内存紧时会拖很久）。
            if found.standardizedFileURL.path.hasPrefix(bundledResourceDirectory.standardizedFileURL.path) {
                return found
            }
            // 若找到沙箱外文件，尽量同步进沙箱目录，避免下次仍“未下载”
            let sandboxURL = localPath(for: model)
            if found.standardizedFileURL.path != sandboxURL.standardizedFileURL.path {
                try? FileManager.default.createDirectory(
                    at: sandboxURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if !FileManager.default.fileExists(atPath: sandboxURL.path) {
                    try? FileManager.default.copyItem(at: found, to: sandboxURL)
                }
                if FileManager.default.fileExists(atPath: sandboxURL.path) {
                    return sandboxURL
                }
            }
            return found
        }
        return nil
    }

    static func resolveVADPath() -> URL? {
        if let found = existingPath(for: vadFileName, minimumBytes: 50_000) {
            if found.standardizedFileURL.path.hasPrefix(bundledResourceDirectory.standardizedFileURL.path) {
                return found
            }
            let sandboxURL = vadPath
            if found.standardizedFileURL.path != sandboxURL.standardizedFileURL.path {
                try? FileManager.default.createDirectory(
                    at: sandboxURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if !FileManager.default.fileExists(atPath: sandboxURL.path) {
                    try? FileManager.default.copyItem(at: found, to: sandboxURL)
                }
                if FileManager.default.fileExists(atPath: sandboxURL.path) {
                    return sandboxURL
                }
            }
            return found
        }
        return nil
    }

    static func isModelAvailable(_ model: FunASRModel = .sensevoiceSmallQ8) -> Bool {
        resolveModelPath(model) != nil
    }

    static var isVADAvailable: Bool {
        resolveVADPath() != nil
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
