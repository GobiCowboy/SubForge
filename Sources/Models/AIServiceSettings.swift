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

    var isLocal: Bool {
        switch self {
        case .funASRLocal, .whisperLocal, .appleSpeech:
            true
        case .officialSmart, .cloudASR:
            false
        }
    }
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
