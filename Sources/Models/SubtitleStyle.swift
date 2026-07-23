import CryptoKit
import Foundation

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
