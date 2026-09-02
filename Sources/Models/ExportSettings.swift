import CryptoKit
import Foundation

struct ExportSettings: Equatable, Codable {
    static let frameRatePresets = [24, 25, 30, 50, 60]
    static let minimumFrameRate = 1
    static let maximumFrameRate = 240

    var format: ExportFormat = .srtAndFCPXML
    var fps: Int = 30
    var width: Int = 1920
    var height: Int = 1080
    var namingRule = "{project_name}_{date}"
    var saveLocation: SaveLocation = .sameAsSource
    var customOutputPath: String = ""
    var customOutputBookmarkData: Data?
    var sourceOutputPath: String = ""
    var sourceOutputBookmarkData: Data?
    var overwriteExisting = true
    var includeLog = true
    var exportToFinalCutPro = true

    enum CodingKeys: String, CodingKey {
        case format
        case fps
        case width
        case height
        case namingRule
        case saveLocation
        case customOutputPath
        case customOutputBookmarkData
        case sourceOutputPath
        case sourceOutputBookmarkData
        case overwriteExisting
        case includeLog
        case exportToFinalCutPro
    }

    init() {}

    static func clampFrameRate(_ value: Int) -> Int {
        min(max(value, minimumFrameRate), maximumFrameRate)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        format = try container.decodeIfPresent(ExportFormat.self, forKey: .format) ?? .srtAndFCPXML
        fps = Self.clampFrameRate(try container.decodeIfPresent(Int.self, forKey: .fps) ?? 30)
        width = try container.decodeIfPresent(Int.self, forKey: .width) ?? 1920
        height = try container.decodeIfPresent(Int.self, forKey: .height) ?? 1080
        namingRule = try container.decodeIfPresent(String.self, forKey: .namingRule) ?? "{project_name}_{date}"
        saveLocation = try container.decodeIfPresent(SaveLocation.self, forKey: .saveLocation) ?? .sameAsSource
        customOutputPath = try container.decodeIfPresent(String.self, forKey: .customOutputPath) ?? ""
        customOutputBookmarkData = try container.decodeIfPresent(Data.self, forKey: .customOutputBookmarkData)
        sourceOutputPath = try container.decodeIfPresent(String.self, forKey: .sourceOutputPath) ?? ""
        sourceOutputBookmarkData = try container.decodeIfPresent(Data.self, forKey: .sourceOutputBookmarkData)
        overwriteExisting = try container.decodeIfPresent(Bool.self, forKey: .overwriteExisting) ?? true
        includeLog = try container.decodeIfPresent(Bool.self, forKey: .includeLog) ?? true
        exportToFinalCutPro = try container.decodeIfPresent(Bool.self, forKey: .exportToFinalCutPro) ?? true
    }
}

enum ExportFormat: String, CaseIterable, Codable, Identifiable {
    case srt = "SRT"
    case fcpxml = "FCPXML"
    case srtAndFCPXML = "SRT + FCPXML"
    case txt = "TXT"
    case vtt = "VTT"

    var id: String { rawValue }

    var includesFCPXML: Bool {
        self == .fcpxml || self == .srtAndFCPXML
    }
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
