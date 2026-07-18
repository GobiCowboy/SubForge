import Foundation

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "通用"
    case smartService = "智能服务"
    case transcription = "转写"
    case proofreading = "校对"
    case subtitle = "基本样式"
    case export = "导出"
    case watch = "目录监听"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .smartService: "sparkles.rectangle.stack"
        case .transcription: "waveform"
        case .proofreading: "text.badge.checkmark"
        case .subtitle: "captions.bubble"
        case .export: "square.and.arrow.up"
        case .watch: "folder.badge.gearshape"
        }
    }

    var description: String {
        switch self {
        case .general:
            "界面语言与基础入口"
        case .smartService:
            "购买官方智能字幕时长，查看额度和中国区服务状态"
        case .transcription:
            "决定素材如何被识别成可编辑字幕"
        case .proofreading:
            "校对是增强层，主要减少人工清理成本，不应该改写原意"
        case .subtitle:
            "定义导出字幕的基础观感与版式位置"
        case .export:
            "定义最终字幕产物的格式、参数与输出落点"
        case .watch:
            "通过自动监听目录，把转写、校对、导出串成自动化工作流"
        }
    }
}
