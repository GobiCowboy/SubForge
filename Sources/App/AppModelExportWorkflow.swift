import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

extension AppModel {
    func exportArtifacts() {
        guard !segments.isEmpty else { return }

        configureFirstExportDirectoryIfNeeded()

        guard let directoryChoice = chooseExportDirectory() else { return }
        let baseName = currentDocumentURL?.deletingPathExtension().lastPathComponent ?? "SubForge Export"

        do {
            try performExport(baseName: baseName, directory: directoryChoice.url)
        } catch {
            if isFileWritePermissionError(error),
               settings.exportSettings.saveLocation == .sameAsSource,
               let sourceDirectory = currentDocumentURL?.deletingLastPathComponent() {
                guard let authorizedDirectory = authorizeSourceExportDirectory(sourceDirectory) else {
                    return
                }
                do {
                    try performExport(baseName: baseName, directory: authorizedDirectory.url)
                    return
                } catch {
                    showToast("导出失败：\(error.localizedDescription)", level: .error)
                    return
                }
            }
            showToast("导出失败：\(error.localizedDescription)", level: .error)
        }
    }

    func performExport(baseName: String, directory: URL) throws {
        let plan = makeExportPlan(baseName: baseName, directory: directory)
        var exportedURLs: [URL] = []

        if let srtURL = plan.srtURL {
            try SRTCodec.generate(segments).write(to: srtURL, atomically: true, encoding: .utf8)
            exportedURLs.append(srtURL)
        }

        if let fcpxmlURL = plan.fcpxmlURL {
            try makeFCPXML(projectName: baseName, segments: segments).write(to: fcpxmlURL, atomically: true, encoding: .utf8)
            exportedURLs.append(fcpxmlURL)
        }

        if settings.exportSettings.exportToFinalCutPro,
           let fcpxmlURL = plan.fcpxmlURL,
           !finalCutProApplicationURLs().isEmpty {
            try importIntoFinalCutPro(fcpxmlURL)
            showToast("已导出并发送到 Final Cut Pro", level: .success)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(exportedURLs)
            showToast("已导出 \(plan.summary)", level: .success)
        }
    }

    func configureFirstExportDirectoryIfNeeded() {
        guard FirstExportDirectoryOnboarding.shouldPresent(for: settings),
              let sourceDirectory = currentDocumentURL?.deletingLastPathComponent(),
              let selection = FirstExportDirectoryOnboarding.present(
                defaultDirectory: suggestedWatchRootDirectory(),
                sourceDirectory: sourceDirectory
              ) else {
            return
        }

        var updated = settings
        let bookmarkData = SecurityScopedResourceAccess.bookmarkData(for: selection.directoryURL)
        updated.exportSettings.sourceOutputPath = selection.directoryURL.path
        updated.exportSettings.sourceOutputBookmarkData = bookmarkData

        if selection.mode == .enableAutomaticMonitoring {
            updated.watchSettings.directoryPath = selection.directoryURL.path
            updated.watchSettings.directoryBookmarkData = bookmarkData
            updated.watchSettings.autoStart = true
        }
        settings = updated

        if selection.mode == .enableAutomaticMonitoring {
            AppLog.watcher.info(
                "watch onboarding configured directory=\(selection.directoryURL.path, privacy: .public)"
            )
            showToast(
                "已启用自动监听：\(selection.directoryURL.lastPathComponent)",
                level: .success
            )
        } else {
            AppLog.export.info(
                "export scope configured directory=\(selection.directoryURL.path, privacy: .public)"
            )
        }
    }

    func suggestedWatchRootDirectory() -> URL? {
        guard let sourceDirectory = currentDocumentURL?.deletingLastPathComponent() else {
            return nil
        }

        let parentDirectory = sourceDirectory.deletingLastPathComponent()
        guard parentDirectory.path != sourceDirectory.path else {
            return sourceDirectory
        }
        return parentDirectory
    }

    func dismissToast(_ toast: ToastMessage) {
        if self.toast == toast {
            self.toast = nil
        }
    }

    func presentShortcutGuide() {
        isShortcutGuidePresented = true
    }

    func presentSettings() {
        SubForgeAppDelegate.showDockIcon()
        _ = MainWindowController.shared.showWindow()
        settingsWindowPresenter?()
    }

    func openImportPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = Self.supportedImportExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
        panel.prompt = "打开"
        // 显式创建安全作用域书签，避免仅依赖瞬时 powerbox 路径。
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true)
        if panel.runModal() == .OK, let url = panel.url {
            // 保留 panel 返回的原始 URL（含 security scope），不要 standardizedFileURL。
            importDocument(at: url)
        }
    }

    func addRecentProject(for url: URL, kind: String, subtitleCount: Int) {
        let project = RecentProject(
            name: url.lastPathComponent,
            path: url.path,
            kind: kind,
            durationLabel: formatDuration(playbackDuration),
            modifiedLabel: RelativeDateTimeFormatter().localizedString(for: Date(), relativeTo: Date()),
            subtitleCount: subtitleCount,
            bookmarkData: SecurityScopedResourceAccess.bookmarkData(for: url)
        )
        recentProjects.removeAll { $0.path == project.path }
        recentProjects.insert(project, at: 0)
        if recentProjects.count > 8 {
            recentProjects = Array(recentProjects.prefix(8))
        }
    }

    func blankSegment(around index: Int, before: Bool) -> SubtitleSegment {
        let current = segments[index]
        let start: TimeInterval
        let end: TimeInterval

        if before {
            let previousEnd = index > 0 ? segments[index - 1].end : max(0, current.start - 1)
            start = previousEnd
            end = max(current.start, start + 1)
        } else {
            start = current.end
            let nextStart = index + 1 < segments.count ? segments[index + 1].start : current.end + 1.5
            end = max(nextStart, start + 1)
        }

        return SubtitleSegment(start: start, end: end, text: "")
    }

    func notifyUser(_ text: String, level: ToastMessage.Level = .info, duration: TimeInterval = 3.5) {
        showToast(text, level: level, duration: duration)
    }

    func showToast(_ text: String, level: ToastMessage.Level, duration: TimeInterval = 3) {
        let message = ToastMessage(text: text, level: level)
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(duration))
            await MainActor.run {
                self.dismissToast(message)
            }
        }
    }

    struct ExportPlan {
        let srtURL: URL?
        let fcpxmlURL: URL?
        let summary: String
    }

}
