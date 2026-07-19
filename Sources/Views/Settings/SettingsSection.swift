import Foundation

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "通用"
    case subtitles = "字幕"
    case style = "样式"
    case export = "导出"
    case watch = "目录监听"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .subtitles: "captions.bubble"
        case .style: "textformat"
        case .export: "square.and.arrow.up"
        case .watch: "folder.badge.gearshape"
        }
    }

    var description: String {
        switch self {
        case .general:
            "界面语言与基础入口"
        case .subtitles:
            "选择字幕方案，官方即用或自定义处理"
        case .style:
            "定义导出字幕的基础观感与版式位置"
        case .export:
            "定义最终字幕产物的格式、参数与输出落点"
        case .watch:
            "通过自动监听目录，把转写、校对、导出串成自动化工作流"
        }
    }
}
