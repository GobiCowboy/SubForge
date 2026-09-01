import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

extension AppModel {
    var selectedSegment: SubtitleSegment? {
        guard let selectedSegmentID else { return nil }
        return segments.first(where: { $0.id == selectedSegmentID })
    }

    var selectedIndex: Int? {
        guard let selectedSegmentID else { return nil }
        return segments.firstIndex(where: { $0.id == selectedSegmentID })
    }

    var currentDocumentName: String {
        currentDocumentURL?.lastPathComponent ?? "未命名项目"
    }

    var currentProjectTitle: String {
        currentDocumentURL?.deletingPathExtension().lastPathComponent ?? "当前字幕"
    }

    var canExport: Bool {
        !segments.isEmpty
    }

    var hasWorkspace: Bool {
        currentDocumentURL != nil || !segments.isEmpty || mode == .progress
    }

    var summaryLanguage: String {
        settings.language == "zh-CN" ? "中文" : settings.language
    }

    func requestImportFromMenu() {
        openImportPanel()
    }

    func activateMainWindow() {
        AppLog.lifecycle.info("activate main window requested visibleWindows=\(NSApp.windows.filter { $0.isVisible }.count, privacy: .public) allWindows=\(NSApp.windows.count, privacy: .public)")

        SubForgeAppDelegate.showDockIcon()
        NSApp.unhide(nil)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)

        if MainWindowController.shared.showWindow() {
            NSApp.arrangeInFront(nil)
            return
        }

        guard let window = preferredMainWindow() else {
            AppLog.lifecycle.warning("activate main window skipped, no app window available")
            return
        }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.arrangeInFront(nil)
    }

    func preferredMainWindow() -> NSWindow? {
        NSApp.windows.first { window in
            window.isVisible && window.canBecomeMain
        } ?? NSApp.windows.first { window in
            window.canBecomeMain
        } ?? NSApp.windows.first
    }

    func showHome() {
        stopPlayback(captureTimestamp: false)
        if mode == .progress {
            pipelineTask?.cancel()
            pipelineTask = nil
            stopPipelineClock()
        }
        mode = .home
    }

    func showEditor() {
        guard !segments.isEmpty else { return }
        mode = .editor
    }

    func resetWorkspace() {
        stopPlayback(captureTimestamp: false)
        hotwordPromptRequest = nil
        let wasProcessing = mode == .progress
        pipelineTask?.cancel()
        pipelineTask = nil
        stopPipelineClock()
        Task {
            await FunASRCLIRunner.shared.cancelActive()
        }
        mode = .home
        pipelineStages = Self.makePipelineStages(
            proofreadingEnabled: settings.shouldRunProofreading,
            officialSmart: settings.transcriptionEngine == .officialSmart
        )
        pipelineProgress = 0
        pipelineMessage = "等待开始"
        currentDocumentURL = nil
        currentDocumentAccess = nil
        segments = []
        selectedSegmentID = nil
        subtitleTextCaret = nil
        currentTime = 0
        playbackDuration = 0
        waveformSamples = []
        isEditingSubtitle = false
        editorFocusContext = .none
        activeEditorSurface = .table
        clearPlaybackMedia()
        if wasProcessing {
            showToast("已取消当前任务", level: .info, duration: 3)
        }
    }

    func importDocument(at url: URL) {
        let ext = url.pathExtension.lowercased()
        guard Self.supportedImportExtensions.contains(ext) else {
            showToast("不支持该文件格式，请导入音频文件或 SRT", level: .error)
            AppLog.import.warning("unsupported import extension=\(ext, privacy: .public) file=\(url.lastPathComponent, privacy: .public)")
            return
        }

        if ext == "srt" {
            importSRT(from: url)
        } else {
            // 必须保留 open panel / drop 返回的原始 URL，不要 standardizedFileURL，
            // 否则可能丢掉 security-scoped 访问令牌，后续 AVPlayer 静默失败。
            currentDocumentAccess = SecurityScopedResourceAccess(url: url)
            currentDocumentURL = url
            prepareMediaPreview(for: url)
            startTranscription(for: url)
        }
    }

    func startWatchFolder() {
        var updated = settings
        updated.watchSettings.autoStart = true
        settings = updated
        applyWatchSettings(updated)
    }

    func stopWatchFolder() {
        var updated = settings
        updated.watchSettings.autoStart = false
        settings = updated
        watchFolderService.stop()
        watchDirectoryAccess = nil
        syncWatchState()
    }

    func bindWatchFolderService() {
        watchFolderService.onStateChange = { [weak self] in
            self?.syncWatchState()
        }

        watchFolderService.onDetectedFCPAudio = { [weak self] url in
            self?.handleDetectedFCPAudio(url) ?? false
        }

        syncWatchState()
    }

    func applyWatchSettings(_ settings: AppSettings) {
        let path = settings.watchSettings.directoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard settings.watchSettings.autoStart, !path.isEmpty else {
            AppLog.watcher.info("watch disabled autoStart=\(settings.watchSettings.autoStart, privacy: .public) pathEmpty=\(path.isEmpty, privacy: .public)")
            watchFolderService.stop()
            watchDirectoryAccess = nil
            syncWatchState()
            return
        }

        guard let access = SecurityScopedResourceAccess(
            bookmarkData: settings.watchSettings.directoryBookmarkData,
            fallbackPath: path,
            isDirectory: true
        ) else {
            AppLog.watcher.error("watch start failed, directory access unavailable path=\(path, privacy: .public)")
            watchFolderService.stop()
            watchDirectoryAccess = nil
            syncWatchState()
            return
        }

        AppLog.watcher.info("watch apply settings path=\(access.url.path, privacy: .public)")
        watchDirectoryAccess = access
        watchFolderService.start(watching: access.url)
        syncWatchState()
    }

    func syncWatchState() {
        isWatchingDirectory = watchFolderService.isWatching
        watchStatusMessage = watchFolderService.statusMessage
        watchedFileCount = watchFolderService.processedCount
        menuBarController.refreshMenu()
    }

    func handleDetectedFCPAudio(_ url: URL) -> Bool {
        guard pipelineTask == nil, hotwordPromptRequest == nil else {
            AppLog.watcher.info("watch detected \(url.lastPathComponent, privacy: .public), but pipeline is busy")
            return false
        }

        AppLog.watcher.info("watch accepted FCP audio \(url.path, privacy: .public)")
        activateMainWindow()
        showToast("监听到 FCP 音频：\(url.lastPathComponent)", level: .info)
        importDocument(at: url)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.activateMainWindow()
        }
        return true
    }

    func openRecentProject(_ project: RecentProject) {
        let url = URL(fileURLWithPath: project.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            recentProjects.removeAll { $0.id == project.id }
            showToast("最近项目已失效，已从列表移除", level: .error)
            return
        }

        if let access = SecurityScopedResourceAccess(
            bookmarkData: project.bookmarkData,
            fallbackPath: project.path,
            isDirectory: false
        ), access.hasAccess {
            importDocument(at: access.url)
        } else if let authorizedURL = requestAccessForRecentProject(project) {
            importDocument(at: authorizedURL)
        } else {
            showToast("需要重新授权才能打开这个文件", level: .error, duration: 4)
        }
    }

    func requestAccessForRecentProject(_ project: RecentProject) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = Self.supportedImportExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
        panel.prompt = "重新授权"
        panel.message = "重新选择这个文件，SubForge 才能在沙盒中继续读取它。"
        panel.directoryURL = URL(fileURLWithPath: project.path).deletingLastPathComponent()
        panel.nameFieldStringValue = project.name

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
