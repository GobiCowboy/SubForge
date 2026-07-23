import AppKit

/// 将 App Sandbox 的目录授权限制在一个原生文件面板边界内。
@MainActor
enum ExportDirectoryAuthorization {
    static func requestAccess(to suggestedDirectory: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "允许访问源文件夹"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "允许并导出"
        panel.message = "为了把字幕保存在源文件旁边，请选择源文件所在文件夹“\(suggestedDirectory.lastPathComponent)”。这只授权导出，不会开启自动监听。"
        panel.directoryURL = suggestedDirectory.deletingLastPathComponent()
        panel.nameFieldStringValue = suggestedDirectory.lastPathComponent

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
