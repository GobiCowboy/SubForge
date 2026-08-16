import AppKit

/// 将 App Sandbox 的目录授权限制在一个原生文件面板边界内。
@MainActor
enum ExportDirectoryAuthorization {
    static func requestAccess(to authorizationRoot: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "允许访问上级目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "允许访问"
        panel.message = "允许访问“\(authorizationRoot.lastPathComponent)”文件夹"
        panel.directoryURL = authorizationRoot.deletingLastPathComponent()
        panel.nameFieldStringValue = authorizationRoot.lastPathComponent

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    static func presentInvalidSelection(
        selectedDirectory: URL,
        requiredSourceDirectory: URL
    ) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "所选目录无法用于导出"
        alert.informativeText = "“\(selectedDirectory.lastPathComponent)”不包含音频所在的“\(requiredSourceDirectory.lastPathComponent)”文件夹。请选择该文件夹的上级目录。"
        alert.addButton(withTitle: "重新选择")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
