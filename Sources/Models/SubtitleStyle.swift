import Foundation

/// 字幕样式配置
struct SubtitleStyle: Equatable, Codable {
    var fontFamily: String = "PingFang SC"
    var fontSize: Int = 48
    var fontColor: String = "#FFFFFF"       // 白色
    var outlineColor: String = "#000000"    // 黑色描边
    var outlineWidth: Double = 2.0
    var position: SubtitlePosition = .bottomCenter
    var bottomMargin: Int = 60              // 距底部像素
}

enum SubtitlePosition: String, CaseIterable, Codable {
    case bottomCenter = "底部居中"
    case topCenter = "顶部居中"
    case custom = "自定义"
}
