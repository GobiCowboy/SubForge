import Foundation

struct SettingsValidationState: Equatable, Codable {
    var hasValidated = false
    var passed = false
    var resultText = "还没有执行验证"
}

struct AppSettings: Equatable, Codable {
    var interfaceLanguage: InterfaceLanguage = .simplifiedChinese
    var showMenuBarIcon = true

    var transcriptionEngine: TranscriptionEngine = .appleSpeech
    var whisperModel: WhisperModel = .base
    var cloudASRPreset: CloudASRPreset = .dashscope
    var cloudASRURL: String = CloudASRPreset.dashscope.defaultURL
    var cloudASRKey: String = ""
    var cloudASRModel: String = CloudASRPreset.dashscope.defaultModel
    var language: String = "zh-CN"
    var sentenceSplitStrategy: SentenceSplitStrategy = .punctuation
    var maxSubtitleLength: Int? = 24
    var keepFillerWords = false
    var transcriptionValidationState = SettingsValidationState()

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

    var effectiveMaxSubtitleLength: Int {
        min(max(maxSubtitleLength ?? 24, 10), 50)
    }

    var effectiveLLMURL: String {
        cloudLLMURL.isEmpty ? cloudLLMPreset.defaultURL : cloudLLMURL
    }

    var effectiveLLMModel: String {
        cloudLLMModel.isEmpty ? cloudLLMPreset.defaultModel : cloudLLMModel
    }
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

struct ExportSettings: Equatable, Codable {
    var format: ExportFormat = .srtAndFCPXML
    var fps: Int = 30
    var width: Int = 1920
    var height: Int = 1080
    var namingRule = "{project_name}_{date}"
    var saveLocation: SaveLocation = .sameAsSource
    var customOutputPath: String = ""
    var customOutputBookmarkData: Data?
    var overwriteExisting = false
    var includeLog = true
    var exportToFinalCutPro = false

    enum CodingKeys: String, CodingKey {
        case format
        case fps
        case width
        case height
        case namingRule
        case saveLocation
        case customOutputPath
        case customOutputBookmarkData
        case overwriteExisting
        case includeLog
        case exportToFinalCutPro
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        format = try container.decodeIfPresent(ExportFormat.self, forKey: .format) ?? .srtAndFCPXML
        fps = try container.decodeIfPresent(Int.self, forKey: .fps) ?? 30
        width = try container.decodeIfPresent(Int.self, forKey: .width) ?? 1920
        height = try container.decodeIfPresent(Int.self, forKey: .height) ?? 1080
        namingRule = try container.decodeIfPresent(String.self, forKey: .namingRule) ?? "{project_name}_{date}"
        saveLocation = try container.decodeIfPresent(SaveLocation.self, forKey: .saveLocation) ?? .sameAsSource
        customOutputPath = try container.decodeIfPresent(String.self, forKey: .customOutputPath) ?? ""
        customOutputBookmarkData = try container.decodeIfPresent(Data.self, forKey: .customOutputBookmarkData)
        overwriteExisting = try container.decodeIfPresent(Bool.self, forKey: .overwriteExisting) ?? false
        includeLog = try container.decodeIfPresent(Bool.self, forKey: .includeLog) ?? true
        exportToFinalCutPro = try container.decodeIfPresent(Bool.self, forKey: .exportToFinalCutPro) ?? false
    }
}

enum ExportFormat: String, CaseIterable, Codable, Identifiable {
    case srt = "SRT"
    case fcpxml = "FCPXML"
    case srtAndFCPXML = "SRT + FCPXML"
    case txt = "TXT"
    case vtt = "VTT"

    var id: String { rawValue }
}

enum SaveLocation: String, CaseIterable, Codable, Identifiable {
    case sameAsSource = "与源文件同目录"
    case customFolder = "自定义目录"

    var id: String { rawValue }
}

struct WatchSettings: Equatable, Codable {
    var directoryPath: String = ""
    var directoryBookmarkData: Data?
    var manualReviewBeforeExport = true
    var autoStart = false
    var newFileAction: WatchAction = .queue
    var errorNotice: ErrorNotice = .systemNotification
}

enum WatchAction: String, CaseIterable, Codable, Identifiable {
    case transcribeImmediately = "立即开始转写"
    case queue = "先加入队列"
    case reviewOnly = "仅提示人工处理"

    var id: String { rawValue }
}

enum ErrorNotice: String, CaseIterable, Codable, Identifiable {
    case systemNotification = "系统通知"
    case modalAlert = "弹窗提醒"
    case logOnly = "只写入日志"

    var id: String { rawValue }
}

struct SubtitleStyle: Equatable, Codable {
    var canvasOrientation: SubtitleCanvasOrientation = .landscape
    var preset: SubtitleStylePreset = .whiteTextBlackOutline
    var fontFamily = "PingFang SC"
    var fontSize: Double = 56
    var fontWeight: SubtitleFontWeight = .semibold
    var horizontalAlignment: SubtitleHorizontalAlignment = .center
    var fontColorHex = "#FFFFFF"
    var lineSpacing: Double = 0
    var characterSpacing: Double = 0
    var position: SubtitlePosition = .bottom
    var offsetX: Double = 0
    var offsetY: Double = -28
    var positionX: Double = 0
    var positionY: Double = -467
    var positionZ: Double = 0
    var surfaceEnabled = false
    var surfaceColorHex = "#111111"
    var surfaceOpacity: Double = 0.72
    var surfaceBlur: Double = 0
    var outlineEnabled = true
    var outlineColorHex = "#111111"
    var outlineOpacity: Double = 1
    var outlineBlur: Double = 0
    var outlineWidth: Double = 2
    var shadowEnabled = false
    var shadowColorHex = "#000000"
    var shadowOpacity: Double = 0.35
    var shadowBlur: Double = 10
    var shadowOffsetY: Double = 4

    enum CodingKeys: String, CodingKey {
        case canvasOrientation
        case preset
        case fontFamily
        case fontSize
        case fontWeight
        case horizontalAlignment
        case fontColorHex
        case lineSpacing
        case characterSpacing
        case position
        case offsetX
        case offsetY
        case positionX
        case positionY
        case positionZ
        case surfaceEnabled
        case surfaceColorHex
        case surfaceOpacity
        case surfaceBlur
        case outlineEnabled
        case outlineColorHex
        case outlineOpacity
        case outlineBlur
        case outlineWidth
        case shadowEnabled
        case shadowColorHex
        case shadowOpacity
        case shadowBlur
        case shadowOffsetY
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        canvasOrientation = try container.decodeIfPresent(SubtitleCanvasOrientation.self, forKey: .canvasOrientation) ?? .landscape
        preset = try container.decodeIfPresent(SubtitleStylePreset.self, forKey: .preset) ?? .whiteTextBlackOutline
        fontFamily = try container.decodeIfPresent(String.self, forKey: .fontFamily) ?? "PingFang SC"
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? 56
        fontWeight = try container.decodeIfPresent(SubtitleFontWeight.self, forKey: .fontWeight) ?? .semibold
        horizontalAlignment = try container.decodeIfPresent(SubtitleHorizontalAlignment.self, forKey: .horizontalAlignment) ?? .center
        fontColorHex = try container.decodeIfPresent(String.self, forKey: .fontColorHex) ?? "#FFFFFF"
        lineSpacing = try container.decodeIfPresent(Double.self, forKey: .lineSpacing) ?? 0
        characterSpacing = try container.decodeIfPresent(Double.self, forKey: .characterSpacing) ?? 0
        position = try container.decodeIfPresent(SubtitlePosition.self, forKey: .position) ?? .bottom
        offsetX = try container.decodeIfPresent(Double.self, forKey: .offsetX) ?? 0
        offsetY = try container.decodeIfPresent(Double.self, forKey: .offsetY) ?? -28
        positionX = try container.decodeIfPresent(Double.self, forKey: .positionX) ?? 0
        positionY = try container.decodeIfPresent(Double.self, forKey: .positionY)
            ?? (canvasOrientation == .landscape ? -467 : -495)
        positionZ = try container.decodeIfPresent(Double.self, forKey: .positionZ) ?? 0
        surfaceEnabled = try container.decodeIfPresent(Bool.self, forKey: .surfaceEnabled) ?? false
        surfaceColorHex = try container.decodeIfPresent(String.self, forKey: .surfaceColorHex) ?? "#111111"
        surfaceOpacity = try container.decodeIfPresent(Double.self, forKey: .surfaceOpacity) ?? 0.72
        surfaceBlur = try container.decodeIfPresent(Double.self, forKey: .surfaceBlur) ?? 0
        outlineEnabled = try container.decodeIfPresent(Bool.self, forKey: .outlineEnabled) ?? true
        outlineColorHex = try container.decodeIfPresent(String.self, forKey: .outlineColorHex) ?? "#111111"
        outlineOpacity = try container.decodeIfPresent(Double.self, forKey: .outlineOpacity) ?? 1
        outlineBlur = try container.decodeIfPresent(Double.self, forKey: .outlineBlur) ?? 0
        outlineWidth = try container.decodeIfPresent(Double.self, forKey: .outlineWidth) ?? 2
        shadowEnabled = try container.decodeIfPresent(Bool.self, forKey: .shadowEnabled) ?? false
        shadowColorHex = try container.decodeIfPresent(String.self, forKey: .shadowColorHex) ?? "#000000"
        shadowOpacity = try container.decodeIfPresent(Double.self, forKey: .shadowOpacity) ?? 0.35
        shadowBlur = try container.decodeIfPresent(Double.self, forKey: .shadowBlur) ?? 10
        shadowOffsetY = try container.decodeIfPresent(Double.self, forKey: .shadowOffsetY) ?? 4
    }
}

enum SubtitleFontWeight: String, CaseIterable, Codable, Identifiable {
    case regular = "常规"
    case medium = "中等"
    case semibold = "半粗"
    case bold = "加粗"

    var id: String { rawValue }
}

enum SubtitlePosition: String, CaseIterable, Codable, Identifiable {
    case top = "顶部"
    case middle = "中部"
    case bottom = "底部"

    var id: String { rawValue }
}

enum SubtitleHorizontalAlignment: String, CaseIterable, Codable, Identifiable {
    case leading = "左对齐"
    case center = "居中"
    case trailing = "右对齐"

    var id: String { rawValue }
}

enum SubtitleCanvasOrientation: String, CaseIterable, Codable, Identifiable {
    case landscape = "横屏"
    case portrait = "竖屏"

    var id: String { rawValue }
}

enum SubtitleStylePreset: String, CaseIterable, Codable, Identifiable {
    case whiteTextBlackOutline = "内白外黑"
    case blackTextWhiteOutline = "内黑外白"
    case whiteTextDarkFill = "白字黑底"
    case yellowTextBlackOutline = "黄字黑边"
    case whiteTextBlueFill = "白字蓝底"

    var id: String { rawValue }
}
