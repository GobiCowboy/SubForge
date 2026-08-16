import AppKit
import Foundation

enum FirstExportDirectoryMode {
    case enableAutomaticMonitoring
    case exportOnly
}

struct FirstExportDirectorySelection {
    let mode: FirstExportDirectoryMode
    let directoryURL: URL
}

/// 首次导出时解释视频创作总目录，并让用户明确选择是否开启自动监听。
enum FirstExportDirectoryOnboarding {
    private static let promptShownKey = "subforge.firstExportDirectoryPromptShown"

    static func shouldPresent(for settings: AppSettings) -> Bool {
        !UserDefaults.standard.bool(forKey: promptShownKey)
            && settings.watchSettings.directoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && settings.exportSettings.sourceOutputBookmarkData == nil
    }

    static func present(
        defaultDirectory: URL?,
        sourceDirectory: URL
    ) -> FirstExportDirectorySelection? {
        let alert = NSAlert()
        alert.messageText = "是否开启自动监听？"
        alert.informativeText = """
        接下来请选择“视频创作总目录”，也就是存放所有视频项目文件夹的上级总目录。

        例如当前音频位于“视频创作 / 项目 A / 音频.wav”，应选择“视频创作”，而不是“项目 A”。它通常是当前音频文件的上上级目录，字幕仍会导出到当前音频所在文件夹。
        """
        alert.addButton(withTitle: "开启自动监听")
        alert.addButton(withTitle: "暂不开启")

        let mode: FirstExportDirectoryMode
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            mode = .enableAutomaticMonitoring
        case .alertSecondButtonReturn:
            mode = .exportOnly
        default:
            return nil
        }
        UserDefaults.standard.set(true, forKey: promptShownKey)

        while true {
            let panel = makeDirectoryPanel(
                defaultDirectory: defaultDirectory,
                sourceDirectory: sourceDirectory
            )
            guard panel.runModal() == .OK, let selectedURL = panel.url else {
                return nil
            }
            if isParentDirectory(selectedURL, of: sourceDirectory) {
                return FirstExportDirectorySelection(mode: mode, directoryURL: selectedURL)
            }
            guard presentInvalidDirectoryAlert(
                selectedDirectory: selectedURL,
                sourceDirectory: sourceDirectory
            ) else {
                return nil
            }
        }
    }

    private static func makeDirectoryPanel(
        defaultDirectory: URL?,
        sourceDirectory: URL
    ) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择此总目录"
        panel.title = "选择视频创作总目录"
        panel.message = "请选择“\(sourceDirectory.lastPathComponent)”的上级目录，也就是当前音频文件的上上级目录"
        panel.directoryURL = defaultDirectory
        return panel
    }

    private static func isParentDirectory(_ candidate: URL, of sourceDirectory: URL) -> Bool {
        let candidatePath = candidate.standardizedFileURL.path
        let sourcePath = sourceDirectory.standardizedFileURL.path
        return candidatePath != sourcePath && sourcePath.hasPrefix(candidatePath + "/")
    }

    private static func presentInvalidDirectoryAlert(
        selectedDirectory: URL,
        sourceDirectory: URL
    ) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "请选择视频创作总目录"
        alert.informativeText = "“\(selectedDirectory.lastPathComponent)”不是“\(sourceDirectory.lastPathComponent)”的上级目录。请选择存放所有视频项目文件夹的总目录。"
        alert.addButton(withTitle: "重新选择")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
