import AppKit
import Foundation

/// 首次导出时才引导用户授权视频创作总目录，避免首次启动就请求广泛文件访问。
enum FirstExportWatchFolderOnboarding {
    private static let promptShownKey = "subforge.firstExportWatchFolderPromptShown"

    static func shouldPresent(for settings: AppSettings) -> Bool {
        !UserDefaults.standard.bool(forKey: promptShownKey)
            && settings.watchSettings.directoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 返回用户选中的视频创作总目录；跳过、未勾选或取消选择均返回 `nil`。
    static func present() -> URL? {
        let enableWatchCheckbox = NSButton(
            checkboxWithTitle: "启用自动监听",
            target: nil,
            action: nil
        )
        enableWatchCheckbox.state = .off

        let alert = NSAlert()
        alert.messageText = "设置视频创作总目录"
        alert.informativeText = "选择包含所有视频项目的上级文件夹，例如“视频创作”。SubForge 会监听其子目录中之后新导出的音频，方便下次自动开始处理；不会处理选择前已有的文件。"
        alert.accessoryView = enableWatchCheckbox
        alert.addButton(withTitle: "继续导出")
        alert.addButton(withTitle: "暂不设置")

        defer {
            UserDefaults.standard.set(true, forKey: promptShownKey)
        }

        guard alert.runModal() == .alertFirstButtonReturn,
              enableWatchCheckbox.state == .on
        else {
            return nil
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "使用此目录"
        panel.message = "选择包含多个视频项目的上级目录"
        panel.title = "选择视频创作总目录"

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
