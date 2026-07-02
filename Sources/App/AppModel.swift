import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

enum WorkspaceMode {
    case home
    case progress
    case editor
}

enum EditorFocusContext {
    case none
    case start
    case end
    case text
}

enum EditorSurface {
    case table
    case inspector
}

enum PipelineStage: String, CaseIterable, Identifiable {
    case prepare = "准备文件"
    case transcribe = "语音转写"
    case proofread = "AI 校对"
    case complete = "完成"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .prepare: "folder"
        case .transcribe: "waveform"
        case .proofread: "text.badge.checkmark"
        case .complete: "checkmark.circle"
        }
    }
}

enum PipelineStageStatus {
    case pending
    case active
    case done
}

struct PipelineStageState: Identifiable {
    let stage: PipelineStage
    var status: PipelineStageStatus

    var id: PipelineStage { stage }
}

struct ToastMessage: Identifiable, Equatable {
    enum Level {
        case info
        case success
        case error
    }

    let id = UUID()
    let text: String
    let level: Level
}

@MainActor
final class AppModel: ObservableObject {
    @Published var mode: WorkspaceMode = .home
    @Published var settings = AppSettings()
    @Published var recentProjects: [RecentProject] = RecentProjectsStore.load()
    @Published var currentDocumentURL: URL?
    @Published var segments: [SubtitleSegment] = []
    @Published var selectedSegmentID: UUID?
    @Published var pipelineStages: [PipelineStageState]
    @Published var pipelineProgress: Double = 0
    @Published var pipelineMessage = "等待开始"
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var playbackDuration: TimeInterval = 0
    @Published var playbackRate: Double = 1
    @Published var waveformSamples: [Double] = []
    @Published var isEditingSubtitle = false
    @Published private(set) var capturedTimestamp = ""
    @Published var activeEditorSurface: EditorSurface = .table
    @Published var showInspector = true
    @Published var isShortcutGuidePresented = false
    @Published var toast: ToastMessage?
    @Published private(set) var isWatchingDirectory = false
    @Published private(set) var watchStatusMessage = "未启动"
    @Published private(set) var watchedFileCount = 0

    private var cancellables = Set<AnyCancellable>()
    private var playbackTimer: Timer?
    private var pipelineTask: Task<Void, Never>?
    private let playbackService = MediaPlaybackService()
    private let keyboardMonitor = EditorKeyboardMonitor()
    private let watchFolderService = WatchFolderService()
    private let menuBarController = MenuBarController()
    private var watchDirectoryAccess: SecurityScopedResourceAccess?
    private var waveformTask: Task<Void, Never>?
    @Published private(set) var editorFocusContext: EditorFocusContext = .none

    init() {
        let initialSettings = SettingsStore.load()
        settings = initialSettings
        pipelineStages = Self.makePipelineStages(proofreadingEnabled: initialSettings.proofreadingEnabled)
        menuBarController.bind(model: self)
        SubForgeAppDelegate.applyActivationPolicy(for: initialSettings)
        menuBarController.setVisible(initialSettings.showMenuBarIcon)
        MainWindowController.shared.setHidesDockOnClose(initialSettings.showMenuBarIcon)

        $settings
            .dropFirst()
            .sink { [weak self] settings in
                SettingsStore.save(settings)
                SubForgeAppDelegate.applyActivationPolicy(for: settings)
                MainWindowController.shared.setHidesDockOnClose(settings.showMenuBarIcon)
                self?.menuBarController.setVisible(settings.showMenuBarIcon)
                self?.menuBarController.refreshMenu()
                self?.applyWatchSettings(settings)
            }
            .store(in: &cancellables)

        $recentProjects
            .dropFirst()
            .sink { RecentProjectsStore.save($0) }
            .store(in: &cancellables)

        if recentProjects.isEmpty {
            recentProjects = RecentProject.samples
        }

        playbackService.onTimeUpdate = { [weak self] time in
            guard let self else { return }
            self.handlePlaybackTimeUpdate(time)
        }

        playbackService.onPlaybackFinished = { [weak self] in
            guard let self else { return }
            self.finishPlayback()
        }

        playbackService.onDurationLoaded = { [weak self] duration in
            guard let self else { return }
            self.playbackDuration = max(self.playbackDuration, duration)
        }

        keyboardMonitor.start { [weak self] event in
            self?.handleEditorKeyDown(event) ?? false
        }

        bindWatchFolderService()
        applyWatchSettings(initialSettings)
    }

    deinit {
        playbackTimer?.invalidate()
        pipelineTask?.cancel()
        waveformTask?.cancel()
        watchFolderService.stop()
    }

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

    private func preferredMainWindow() -> NSWindow? {
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
        }
        mode = .home
    }

    func showEditor() {
        guard !segments.isEmpty else { return }
        mode = .editor
    }

    func resetWorkspace() {
        stopPlayback(captureTimestamp: false)
        pipelineTask?.cancel()
        pipelineTask = nil
        mode = .home
        pipelineStages = Self.makePipelineStages(proofreadingEnabled: settings.proofreadingEnabled)
        pipelineProgress = 0
        pipelineMessage = "等待开始"
        currentDocumentURL = nil
        segments = []
        selectedSegmentID = nil
        currentTime = 0
        playbackDuration = 0
        waveformSamples = []
        isEditingSubtitle = false
        editorFocusContext = .none
        activeEditorSurface = .table
        playbackService.clear()
    }

    func importDocument(at url: URL) {
        let ext = url.pathExtension.lowercased()
        if ext == "srt" {
            importSRT(from: url)
        } else {
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

    private func bindWatchFolderService() {
        watchFolderService.onStateChange = { [weak self] in
            self?.syncWatchState()
        }

        watchFolderService.onDetectedFCPAudio = { [weak self] url in
            self?.handleDetectedFCPAudio(url) ?? false
        }

        syncWatchState()
    }

    private func applyWatchSettings(_ settings: AppSettings) {
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

    private func syncWatchState() {
        isWatchingDirectory = watchFolderService.isWatching
        watchStatusMessage = watchFolderService.statusMessage
        watchedFileCount = watchFolderService.processedCount
        menuBarController.refreshMenu()
    }

    private func handleDetectedFCPAudio(_ url: URL) -> Bool {
        guard pipelineTask == nil else {
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
        if FileManager.default.fileExists(atPath: url.path) {
            importDocument(at: url)
        } else {
            recentProjects.removeAll { $0.id == project.id }
            showToast("最近项目已失效，已从列表移除", level: .error)
        }
    }

    func startTranscription(for url: URL) {
        stopPlayback(captureTimestamp: false)
        pipelineTask?.cancel()
        mode = .progress
        currentDocumentURL = url
        segments = []
        selectedSegmentID = nil
        currentTime = 0
        playbackDuration = 0
        pipelineStages = Self.makePipelineStages(proofreadingEnabled: settings.proofreadingEnabled)
        pipelineProgress = 0
        pipelineMessage = "正在准备素材..."

        pipelineTask = Task { [weak self] in
            guard let self else { return }
            do {
                await self.advancePipeline(.prepare, progress: 0.14, message: "正在准备文件与轨道信息…")
                guard !Task.isCancelled else { return }

                var transcriptionSettings = self.settings
                if transcriptionSettings.transcriptionEngine == .whisperLocal,
                   !WhisperRuntime.isCLIAvailable {
                    transcriptionSettings.transcriptionEngine = .appleSpeech
                    self.settings = transcriptionSettings
                    self.showToast("未检测到 Whisper 运行组件，已切换到 Apple 语音继续转写", level: .error)
                }

                let provider = TranscriptionService.createProvider(settings: transcriptionSettings)
                let engineName = transcriptionSettings.transcriptionEngine.rawValue
                self.markStageActive(.transcribe, progress: 0.36, message: "正在使用 \(engineName) 转写…")
                var transcribedSegments = try await provider.transcribe(audioURL: url, language: transcriptionSettings.language)
                transcribedSegments = self.normalizeSegments(transcribedSegments)
                guard !Task.isCancelled else { return }
                self.markStageDone(.transcribe, progress: self.settings.proofreadingEnabled ? 0.72 : 0.92)

                var finalSegments = transcribedSegments
                if self.settings.proofreadingEnabled, let proofreadingProvider = ProofreadingService.createProvider(settings: self.settings) {
                    self.markStageActive(.proofread, progress: 0.8, message: "正在执行模型纠正…")
                    do {
                        let corrected = try await proofreadingProvider.proofread(
                            segments: transcribedSegments,
                            batchSize: 60,
                            prompt: self.settings.proofreadingPrompt,
                            strictCorrections: self.settings.proofreadingStrictCorrections
                        )
                        let normalizedCorrected = self.normalizeSegments(corrected)
                        if normalizedCorrected.isEmpty {
                            finalSegments = transcribedSegments
                            self.showToast("模型纠正返回空结果，已保留原始转写字幕", level: .error)
                        } else {
                            finalSegments = normalizedCorrected
                        }
                        self.markStageDone(.proofread, progress: 0.92)
                    } catch {
                        self.markStageDone(.proofread, progress: 0.92)
                        self.showToast("模型纠正失败，已保留原始转写结果：\(error.localizedDescription)", level: .error)
                    }
                }

                self.markStageActive(.complete, progress: 1.0, message: "字幕已生成，可以开始微调")
                self.segments = finalSegments
                self.selectedSegmentID = finalSegments.first?.id
                self.playbackDuration = (finalSegments.last?.end ?? 0) + 1.5
                self.playbackDuration = max(self.playbackDuration, self.playbackService.mediaDuration)
                self.currentTime = 0
                self.mode = .editor
                self.addRecentProject(for: url, kind: mediaKind(for: url), subtitleCount: finalSegments.count)
                self.markStageDone(.complete, progress: 1.0)
                self.showToast("已生成 \(finalSegments.count) 条字幕", level: .success)
                self.pipelineTask = nil
            } catch {
                self.pipelineTask = nil
                self.mode = .home
                self.pipelineMessage = "转写失败"
                self.showToast("转写失败：\(error.localizedDescription)", level: .error)
            }
        }
    }

    private static func makePipelineStages(proofreadingEnabled: Bool) -> [PipelineStageState] {
        let stages: [PipelineStage] = proofreadingEnabled
            ? [.prepare, .transcribe, .proofread, .complete]
            : [.prepare, .transcribe, .complete]
        return stages.map { PipelineStageState(stage: $0, status: .pending) }
    }

    private func advancePipeline(_ stage: PipelineStage, progress: Double, message: String) async {
        guard !Task.isCancelled else { return }
        for index in pipelineStages.indices {
            switch pipelineStages[index].stage {
            case stage:
                pipelineStages[index].status = .active
            default:
                break
            }
        }
        pipelineMessage = message
        pipelineProgress = progress
        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled else { return }
        for index in pipelineStages.indices where pipelineStages[index].stage == stage {
            pipelineStages[index].status = .done
        }
    }

    private func markStageActive(_ stage: PipelineStage, progress: Double, message: String) {
        for index in pipelineStages.indices {
            switch pipelineStages[index].stage {
            case stage:
                pipelineStages[index].status = .active
            case .prepare where stage != .prepare:
                if pipelineStages[index].status == .active {
                    pipelineStages[index].status = .done
                }
            default:
                break
            }
        }
        pipelineProgress = progress
        pipelineMessage = message
    }

    private func markStageDone(_ stage: PipelineStage, progress: Double) {
        for index in pipelineStages.indices where pipelineStages[index].stage == stage {
            pipelineStages[index].status = .done
        }
        pipelineProgress = progress
    }

    private func normalizeSegments(_ segments: [SubtitleSegment]) -> [SubtitleSegment] {
        segments
            .map { segment in
                var normalized = segment
                normalized.text = normalized.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return normalized
            }
            .filter { !$0.text.isEmpty }
    }

    private func mediaKind(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ["mp4", "mov", "mkv"].contains(ext) {
            return "video"
        }
        return "audio"
    }

    private func importSRT(from url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let parsed = SRTCodec.parse(content)
            guard !parsed.isEmpty else {
                showToast("SRT 文件为空或格式无法识别", level: .error)
                return
            }
            stopPlayback()
            currentDocumentURL = url
            segments = parsed
            selectedSegmentID = parsed.first?.id
            playbackDuration = (parsed.last?.end ?? 0) + 1.5
            currentTime = 0
            waveformSamples = []
            isEditingSubtitle = false
            editorFocusContext = .none
            activeEditorSurface = .table
            playbackService.clear()
            mode = .editor
            addRecentProject(for: url, kind: "srt", subtitleCount: parsed.count)
            showToast("已导入 \(parsed.count) 条字幕", level: .success)
        } catch {
            showToast("读取 SRT 失败：\(error.localizedDescription)", level: .error)
        }
    }

    func selectSegment(_ segmentID: UUID) {
        selectedSegmentID = segmentID
        if let segment = selectedSegment, !isEditingSubtitle {
            seek(to: segment.start)
        }
    }

    func updateSelectedText(_ text: String) {
        guard let selectedIndex else { return }
        segments[selectedIndex].text = text
    }

    func updateSegmentText(_ text: String, for segmentID: UUID) {
        guard let index = segments.firstIndex(where: { $0.id == segmentID }) else { return }
        segments[index].text = text
    }

    func setEditorFocusContext(_ context: EditorFocusContext) {
        AppLog.editor.info(
            "setEditorFocusContext from=\(String(describing: self.editorFocusContext), privacy: .public) to=\(String(describing: context), privacy: .public) surface=\(String(describing: self.activeEditorSurface), privacy: .public) editing=\(self.isEditingSubtitle, privacy: .public)"
        )
        editorFocusContext = context
    }

    func beginEditingSelectedSubtitle(surface: EditorSurface = .table) {
        guard mode == .editor, !isPlaying, selectedSegmentID != nil else { return }
        AppLog.editor.info(
            "beginEditingSelectedSubtitle surface=\(String(describing: surface), privacy: .public) selected=\(String(describing: self.selectedSegmentID), privacy: .public) currentFocus=\(String(describing: self.editorFocusContext), privacy: .public)"
        )
        activeEditorSurface = surface
        isEditingSubtitle = true
        if editorFocusContext == .none {
            editorFocusContext = .text
        }
    }

    func endEditingSubtitle() {
        guard isEditingSubtitle else { return }
        AppLog.editor.info(
            "endEditingSubtitle surface=\(String(describing: self.activeEditorSurface), privacy: .public) selected=\(String(describing: self.selectedSegmentID), privacy: .public) currentFocus=\(String(describing: self.editorFocusContext), privacy: .public)"
        )
        isEditingSubtitle = false
        editorFocusContext = .none
    }

    func setActiveEditorSurface(_ surface: EditorSurface) {
        activeEditorSurface = surface
    }

    func selectPreviousSegment() {
        guard let selectedIndex, selectedIndex > 0 else { return }
        selectSegment(segments[selectedIndex - 1].id)
    }

    func selectNextSegment() {
        guard let selectedIndex, selectedIndex < segments.count - 1 else { return }
        selectSegment(segments[selectedIndex + 1].id)
    }

    func moveEditingFocus(reverse: Bool) {
        guard isEditingSubtitle else { return }

        let order: [EditorFocusContext] = [.start, .end, .text]
        let current = order.firstIndex(of: editorFocusContext) ?? 0
        let nextIndex: Int

        if reverse {
            nextIndex = current == 0 ? order.count - 1 : current - 1
        } else {
            nextIndex = current == order.count - 1 ? 0 : current + 1
        }

        let target = order[nextIndex]
        AppLog.editor.info(
            "moveEditingFocus reverse=\(reverse, privacy: .public) from=\(String(describing: self.editorFocusContext), privacy: .public) to=\(String(describing: target), privacy: .public) surface=\(String(describing: self.activeEditorSurface), privacy: .public)"
        )

        if activeEditorSurface == .table {
            NSApp.keyWindow?.makeFirstResponder(nil)
            DispatchQueue.main.async {
                AppLog.editor.info(
                    "applyDeferredFocus target=\(String(describing: target), privacy: .public) surface=\(String(describing: self.activeEditorSurface), privacy: .public)"
                )
                self.editorFocusContext = target
            }
        } else {
            editorFocusContext = target
        }
    }

    func updateSelectedStart(from text: String) {
        guard let selectedIndex, let value = parseTimestamp(text) else { return }
        segments[selectedIndex].start = max(0, min(value, segments[selectedIndex].end - 0.1))
    }

    func updateSegmentStart(from text: String, for segmentID: UUID) {
        guard let index = segments.firstIndex(where: { $0.id == segmentID }),
              let value = parseTimestamp(text) else { return }
        segments[index].start = max(0, min(value, segments[index].end - 0.1))
    }

    func updateSelectedEnd(from text: String) {
        guard let selectedIndex, let value = parseTimestamp(text) else { return }
        segments[selectedIndex].end = max(segments[selectedIndex].start + 0.1, value)
        playbackDuration = max(playbackDuration, segments[selectedIndex].end + 0.5)
    }

    func updateSegmentEnd(from text: String, for segmentID: UUID) {
        guard let index = segments.firstIndex(where: { $0.id == segmentID }),
              let value = parseTimestamp(text) else { return }
        segments[index].end = max(segments[index].start + 0.1, value)
        playbackDuration = max(playbackDuration, segments[index].end + 0.5, playbackService.mediaDuration)
    }

    func insertSegment(before: Bool) {
        guard let selectedIndex else { return }
        endEditingSubtitle()
        let newSegment = blankSegment(around: selectedIndex, before: before)
        let insertIndex = before ? selectedIndex : selectedIndex + 1
        segments.insert(newSegment, at: insertIndex)
        selectedSegmentID = newSegment.id
    }

    func mergeWithNext() {
        guard let selectedIndex, selectedIndex < segments.count - 1 else { return }
        endEditingSubtitle()
        let current = segments[selectedIndex]
        let next = segments[selectedIndex + 1]
        segments[selectedIndex].end = max(current.end, next.end)
        segments[selectedIndex].text = [current.text, next.text]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        segments.remove(at: selectedIndex + 1)
    }

    func deleteSelected() {
        guard let selectedIndex else { return }
        endEditingSubtitle()
        segments.remove(at: selectedIndex)
        selectedSegmentID = segments.indices.contains(selectedIndex) ? segments[selectedIndex].id : segments.last?.id
    }

    func togglePlayback() {
        guard mode == .editor else { return }
        if isEditingSubtitle {
            endEditingSubtitle()
        }
        isPlaying ? stopPlayback() : startPlayback()
    }

    func skip(by seconds: TimeInterval) {
        guard mode == .editor else { return }
        seek(to: currentTime + seconds)
    }

    func seek(to time: TimeInterval) {
        currentTime = max(0, min(time, playbackDuration))
        if playbackService.hasLoadedMedia {
            playbackService.seek(to: currentTime)
        }
        syncSelectionToCurrentTime()
    }

    func setPlaybackRate(_ rate: Double) {
        playbackRate = rate
        playbackService.setRate(rate)
    }

    func handleBackwardPlaybackShortcut() {
        AppLog.editor.info(
            "shortcut J currentTime=\(self.currentTime, privacy: .public) playing=\(self.isPlaying, privacy: .public) editing=\(self.isEditingSubtitle, privacy: .public)"
        )
        if isEditingSubtitle {
            endEditingSubtitle()
        }
        stopPlayback(captureTimestamp: false)
        seek(to: currentTime - 1)
        showToast("已后退 1 秒", level: .info)
    }

    func handlePausePlaybackShortcut() {
        AppLog.editor.info(
            "shortcut K currentTime=\(self.currentTime, privacy: .public) playing=\(self.isPlaying, privacy: .public) editing=\(self.isEditingSubtitle, privacy: .public)"
        )
        if isPlaying {
            stopPlayback()
        } else {
            captureCurrentTimestamp()
        }
    }

    func handleForwardPlaybackShortcut() {
        AppLog.editor.info(
            "shortcut L currentTime=\(self.currentTime, privacy: .public) playing=\(self.isPlaying, privacy: .public) editing=\(self.isEditingSubtitle, privacy: .public) rate=\(self.playbackRate, privacy: .public)"
        )
        if isEditingSubtitle {
            endEditingSubtitle()
        }

        let rates: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
        let currentIndex = rates.firstIndex(where: { abs($0 - playbackRate) < 0.001 }) ?? 2
        let targetRate = isPlaying
            ? rates[(currentIndex + 1) % rates.count]
            : rates[currentIndex]

        playbackRate = targetRate
        startPlayback()
        showToast("正向播放 \(String(format: "%.2g", targetRate))x", level: .info)
    }

    func handleSpacePlaybackShortcut() {
        guard mode == .editor else { return }

        AppLog.editor.info(
            "spaceShortcut playing=\(self.isPlaying, privacy: .public) editing=\(self.isEditingSubtitle, privacy: .public) selected=\(String(describing: self.selectedSegmentID), privacy: .public) currentTime=\(self.currentTime, privacy: .public)"
        )

        if isEditingSubtitle {
            endEditingSubtitle()
            startPlayback()
            return
        }

        if isPlaying {
            stopPlayback()
            if selectedSegmentID == nil {
                selectedSegmentID = segments.first?.id
            }
            beginEditingSelectedSubtitle()
            return
        }

        if selectedSegmentID == nil {
            selectedSegmentID = segments.first?.id
        }

        if playbackDuration > 0 {
            startPlayback()
        } else {
            beginEditingSelectedSubtitle()
        }
    }

    private func startPlayback() {
        guard playbackDuration > 0 else { return }
        stopPlayback(captureTimestamp: false)

        if currentTime >= max(playbackDuration - 0.05, 0), playbackDuration > 0.05 {
            currentTime = 0
            if playbackService.hasLoadedMedia {
                playbackService.seek(to: 0)
            }
        }

        isPlaying = true

        if playbackService.hasLoadedMedia {
            playbackService.seek(to: currentTime)
            playbackService.play(rate: playbackRate)
            return
        }

        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.currentTime += 0.05 * self.playbackRate
                if self.currentTime >= self.playbackDuration {
                    self.currentTime = self.playbackDuration
                    self.stopPlayback()
                }
                self.syncSelectionToCurrentTime()
            }
        }
    }

    private func stopPlayback(captureTimestamp: Bool = true) {
        let wasPlaying = isPlaying
        playbackTimer?.invalidate()
        playbackTimer = nil
        playbackService.pause()
        isPlaying = false

        if wasPlaying, captureTimestamp {
            captureCurrentTimestamp()
        }
    }

    private func finishPlayback() {
        currentTime = playbackDuration
        playbackTimer?.invalidate()
        playbackTimer = nil
        isPlaying = false
        syncSelectionToCurrentTime()
    }

    private func handlePlaybackTimeUpdate(_ time: TimeInterval) {
        guard isPlaying else { return }
        currentTime = max(0, min(time, playbackDuration))
        syncSelectionToCurrentTime()
    }

    private func prepareMediaPreview(for url: URL) {
        playbackService.loadMedia(from: url)
        waveformTask?.cancel()
        waveformSamples = []
        waveformTask = Task { [weak self] in
            let samples = await WaveformAnalysisService.analyze(url: url)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.waveformSamples = samples
            }
        }
    }

    private func handleEditorKeyDown(_ event: NSEvent) -> Bool {
        guard mode == .editor else {
            return false
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasUnsupportedModifier = modifiers.contains(.command) || modifiers.contains(.control) || modifiers.contains(.option)
        guard !hasUnsupportedModifier else { return false }

        AppLog.editor.info(
            "keyDown keyCode=\(event.keyCode, privacy: .public) chars=\(event.charactersIgnoringModifiers ?? "", privacy: .public) editing=\(self.isEditingSubtitle, privacy: .public) playing=\(self.isPlaying, privacy: .public) surface=\(String(describing: self.activeEditorSurface), privacy: .public) focus=\(String(describing: self.editorFocusContext), privacy: .public) repeat=\(event.isARepeat, privacy: .public)"
        )

        if isEditingSubtitle {
            switch event.keyCode {
            case 49:
                if modifiers.contains(.shift) {
                    AppLog.editor.info("shiftSpacePassThrough editing=true")
                    return false
                }
                if activeTextInputHasMarkedText() {
                    AppLog.editor.info("imeSpacePassThrough editing=true")
                    return false
                }
                handleSpacePlaybackShortcut()
                return true
            case 48:
                moveEditingFocus(reverse: modifiers.contains(.shift))
                return true
            case 53:
                endEditingSubtitle()
                return true
            default:
                return false
            }
        }

        guard !event.isARepeat else { return false }

        switch event.keyCode {
        case 38:
            handleBackwardPlaybackShortcut()
            return true
        case 40:
            handlePausePlaybackShortcut()
            return true
        case 37:
            handleForwardPlaybackShortcut()
            return true
        case 49:
            handleSpacePlaybackShortcut()
            return true
        case 126:
            selectPreviousSegment()
            return true
        case 125:
            selectNextSegment()
            return true
        case 123:
            skip(by: -1)
            return true
        case 124:
            skip(by: 1)
            return true
        default:
            return false
        }
    }

    private func activeTextInputHasMarkedText() -> Bool {
        if let inputClient = NSApp.keyWindow?.firstResponder as? NSTextInputClient,
           inputClient.hasMarkedText() {
            return true
        }

        if let inputClient = NSApp.keyWindow?.fieldEditor(false, for: nil) as? NSTextInputClient,
           inputClient.hasMarkedText() {
            return true
        }

        return false
    }

    private func captureCurrentTimestamp() {
        let formatted = formatClock(currentTime)
        capturedTimestamp = formatted
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(formatted, forType: .string)
        showToast("已复制时间戳 \(formatted)", level: .info)
    }

    private func syncSelectionToCurrentTime() {
        guard let match = segments.first(where: { currentTime >= $0.start && currentTime < $0.end }) else { return }
        if match.id != selectedSegmentID {
            selectedSegmentID = match.id
        }
    }

    func exportArtifacts() {
        guard !segments.isEmpty else { return }

        do {
            guard let directoryChoice = chooseExportDirectory() else { return }
            let directory = directoryChoice.url

            let baseName = currentDocumentURL?.deletingPathExtension().lastPathComponent ?? "SubForge Export"
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

            if settings.exportSettings.exportToFinalCutPro {
                guard let fcpxmlURL = plan.fcpxmlURL else {
                    showToast("导出到 FCP 需要选择 FCPXML 或 SRT + FCPXML", level: .error)
                    return
                }
                try importIntoFinalCutPro(fcpxmlURL)
                showToast("已导出并发送到 Final Cut Pro", level: .success)
            } else {
                NSWorkspace.shared.activateFileViewerSelecting(exportedURLs)
                showToast("已导出 \(plan.summary)", level: .success)
            }
        } catch {
            showToast("导出失败：\(error.localizedDescription)", level: .error)
        }
    }

    func dismissToast(_ toast: ToastMessage) {
        if self.toast == toast {
            self.toast = nil
        }
    }

    func presentShortcutGuide() {
        isShortcutGuidePresented = true
    }

    func openImportPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio, .movie, UTType(filenameExtension: "srt") ?? .plainText]
        panel.prompt = "打开"
        if panel.runModal() == .OK, let url = panel.url {
            importDocument(at: url)
        }
    }

    private func addRecentProject(for url: URL, kind: String, subtitleCount: Int) {
        let project = RecentProject(
            name: url.lastPathComponent,
            path: url.path,
            kind: kind,
            durationLabel: formatDuration(playbackDuration),
            modifiedLabel: RelativeDateTimeFormatter().localizedString(for: Date(), relativeTo: Date()),
            subtitleCount: subtitleCount
        )
        recentProjects.removeAll { $0.path == project.path }
        recentProjects.insert(project, at: 0)
        if recentProjects.count > 8 {
            recentProjects = Array(recentProjects.prefix(8))
        }
    }

    private func blankSegment(around index: Int, before: Bool) -> SubtitleSegment {
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

    private func showToast(_ text: String, level: ToastMessage.Level) {
        let message = ToastMessage(text: text, level: level)
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run {
                self.dismissToast(message)
            }
        }
    }

    private struct ExportPlan {
        let srtURL: URL?
        let fcpxmlURL: URL?
        let summary: String
    }

    private struct ExportDirectoryChoice {
        let url: URL
        let access: SecurityScopedResourceAccess?
    }

    private func chooseExportDirectory() -> ExportDirectoryChoice? {
        switch settings.exportSettings.saveLocation {
        case .sameAsSource:
            if let directory = currentDocumentURL?.deletingLastPathComponent() {
                return ExportDirectoryChoice(url: directory, access: SecurityScopedResourceAccess(url: directory))
            }
            return askForExportDirectory()
        case .customFolder:
            let path = settings.exportSettings.customOutputPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty {
                guard let access = SecurityScopedResourceAccess(
                    bookmarkData: settings.exportSettings.customOutputBookmarkData,
                    fallbackPath: path,
                    isDirectory: true
                ) else {
                    return nil
                }
                return ExportDirectoryChoice(url: access.url, access: access)
            }
            return askForExportDirectory()
        }
    }

    private func askForExportDirectory() -> ExportDirectoryChoice? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "导出到此处"
        panel.message = "选择导出目录"

        guard panel.runModal() == .OK else { return nil }
        guard let url = panel.url else { return nil }
        return ExportDirectoryChoice(url: url, access: SecurityScopedResourceAccess(url: url))
    }

    private func makeExportPlan(baseName: String, directory: URL) -> ExportPlan {
        let needsFCPXML = settings.exportSettings.exportToFinalCutPro
        let format = settings.exportSettings.format

        let srtURL = shouldExportSRT(format)
            ? exportURL(directory: directory, baseName: baseName, extensionName: "srt")
            : nil
        let fcpxmlURL = (shouldExportFCPXML(format) || needsFCPXML)
            ? exportURL(directory: directory, baseName: baseName, extensionName: "fcpxml")
            : nil

        return ExportPlan(
            srtURL: srtURL,
            fcpxmlURL: fcpxmlURL,
            summary: exportSummary(srtURL: srtURL, fcpxmlURL: fcpxmlURL)
        )
    }

    private func shouldExportSRT(_ format: ExportFormat) -> Bool {
        switch format {
        case .srt, .srtAndFCPXML, .txt, .vtt:
            return true
        case .fcpxml:
            return false
        }
    }

    private func shouldExportFCPXML(_ format: ExportFormat) -> Bool {
        switch format {
        case .fcpxml, .srtAndFCPXML:
            return true
        case .srt, .txt, .vtt:
            return false
        }
    }

    private func exportURL(directory: URL, baseName: String, extensionName: String) -> URL {
        let proposedURL = directory.appendingPathComponent(baseName).appendingPathExtension(extensionName)
        guard !settings.exportSettings.overwriteExisting else {
            return proposedURL
        }

        var candidate = proposedURL
        var index = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(baseName)-\(index)")
                .appendingPathExtension(extensionName)
            index += 1
        }
        return candidate
    }

    private func exportSummary(srtURL: URL?, fcpxmlURL: URL?) -> String {
        switch (srtURL != nil, fcpxmlURL != nil) {
        case (true, true):
            return "SRT 和 FCPXML"
        case (true, false):
            return "SRT"
        case (false, true):
            return "FCPXML"
        case (false, false):
            return "文件"
        }
    }

    private func makeFCPXML(projectName: String, segments: [SubtitleSegment]) -> String {
        let style = settings.subtitleStyle
        let fps = max(settings.exportSettings.fps, 1)
        let format = fcpxmlFormat(for: style.canvasOrientation, fps: fps)
        let totalSeconds = max(playbackDuration, segments.last?.end ?? 1)
        let totalDuration = fcpxmlTime(totalSeconds, fps: fps, minimumFrames: 1)
        let storylineItems = makeFCPXMLStorylineItems(
            segments: segments,
            totalDuration: totalSeconds,
            style: style,
            fps: fps
        )

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE fcpxml>
        <fcpxml version="1.14">
          <resources>
            <format id="r1" name="\(format.name)" frameDuration="1/\(fps)s" width="\(format.width)" height="\(format.height)" colorSpace="1-1-1 (Rec. 709)"/>
            <effect id="r2" name="自定" uid=".../Titles.localized/Build In:Out.localized/Custom.localized/Custom.moti"/>
          </resources>
          <library>
            <event name="SubForge Export">
              <project name="\(escapeXML(projectName))">
                <sequence format="r1" tcStart="0s" tcFormat="NDF" duration="\(totalDuration)" audioLayout="stereo" audioRate="48k">
                  <spine>
                    <gap name="空隙" offset="0s" start="3600s" duration="\(totalDuration)">
                      <spine lane="1" offset="3600s">
        \(storylineItems)
                      </spine>
                    </gap>
                  </spine>
                </sequence>
              </project>
            </event>
          </library>
        </fcpxml>
        """
    }

    private func makeFCPXMLStorylineItems(
        segments: [SubtitleSegment],
        totalDuration: Double,
        style: SubtitleStyle,
        fps: Int
    ) -> String {
        let sortedSegments = segments.sorted { $0.start < $1.start }
        var items: [String] = []
        var cursor: Double = 0
        var blankIndex = 1
        var titleIndex = 1
        let frameDuration = 1 / Double(fps)

        for segment in sortedSegments {
            let start = max(segment.start, cursor)
            if start - cursor >= frameDuration / 2 {
                items.append(makeFCPXMLGap(
                    index: blankIndex,
                    offset: cursor,
                    duration: start - cursor,
                    fps: fps
                ))
                blankIndex += 1
                cursor = start
            }

            let end = max(segment.end, start)
            let duration = max(end - start, frameDuration)
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)

            if text.isEmpty {
                items.append(makeFCPXMLGap(
                    index: blankIndex,
                    offset: start,
                    duration: duration,
                    fps: fps
                ))
                blankIndex += 1
                cursor = max(cursor, end)
                continue
            }

            items.append(makeFCPXMLTitle(
                segment: segment,
                index: titleIndex,
                offset: start,
                duration: duration,
                style: style,
                fps: fps
            ))
            titleIndex += 1
            cursor = max(cursor, end)
        }

        if totalDuration - cursor >= frameDuration / 2 {
            items.append(makeFCPXMLGap(
                index: blankIndex,
                offset: cursor,
                duration: totalDuration - cursor,
                fps: fps
            ))
        }

        return items.joined(separator: "\n")
    }

    private func makeFCPXMLGap(index: Int, offset: Double, duration: Double, fps: Int) -> String {
        let safeDuration = max(duration, 0)
        let name = "Blank \(formatFCPXMLTimestamp(offset))-\(formatFCPXMLTimestamp(offset + safeDuration))"
        return """
                        <gap name="\(escapeXML(name))" offset="\(fcpxmlTime(offset, fps: fps))" duration="\(fcpxmlTime(safeDuration, fps: fps))"/>
        """
    }

    private func makeFCPXMLTitle(
        segment: SubtitleSegment,
        index: Int,
        offset: Double,
        duration: Double,
        style: SubtitleStyle,
        fps: Int
    ) -> String {
        let textStyleID = "ts\(index)"
        let name = escapeXML(firstFCPXMLTitleLine(segment.text, fallback: "Caption \(index)"))
        let position = fcpxmlTitlePosition(style)
        let styleAttributes = fcpxmlTextStyleAttributes(style)

        return """
                        <title ref="r2" offset="\(fcpxmlTime(offset, fps: fps))" name="\(name)" duration="\(fcpxmlTime(duration, fps: fps, minimumFrames: 1))">
                          <param name="位置" key="9999/10199/10201/1/100/101" value="\(position.x) \(position.y) \(position.z)"/>
                          <param name="对齐" key="9999/10199/10201/2/354/1002961760/401" value="1 (居中)"/>
                          <param name="对齐" key="9999/10199/10201/2/373" value="0 (左) 2 (下)"/>
                          <param name="Out Sequencing" key="9999/10199/10201/4/10233/201/202" value="0 (到)"/>
                          <param name="disableDRT" key="3733" value="1"/>
                          <text>
                            <text-style ref="\(textStyleID)">\(escapeXML(segment.text))</text-style>
                          </text>
                          <text-style-def id="\(textStyleID)">
                            <text-style \(styleAttributes)/>
                          </text-style-def>
                          <adjust-colorConform enabled="1" autoOrManual="manual" conformType="conformNone" peakNitsOfPQSource="1000" peakNitsOfSDRToPQSource="203"/>
                        </title>
        """
    }

    private struct FCPXMLFormat {
        let name: String
        let width: Int
        let height: Int
    }

    private func fcpxmlFormat(for orientation: SubtitleCanvasOrientation, fps: Int) -> FCPXMLFormat {
        switch orientation {
        case .landscape:
            FCPXMLFormat(name: "FFVideoFormat1920x1080p\(fps * 100)", width: 1920, height: 1080)
        case .portrait:
            FCPXMLFormat(name: "FFVideoFormat1080x1920p\(fps * 100)", width: 1080, height: 1920)
        }
    }

    private func fcpxmlTime(_ seconds: Double, fps: Int, minimumFrames: Int = 0) -> String {
        let frames = max(Int(round(seconds * Double(fps))), minimumFrames)
        if frames == 0 {
            return "0s"
        }
        return "\(frames)/\(fps)s"
    }

    private func formatFCPXMLTimestamp(_ seconds: Double) -> String {
        let clampedSeconds = max(seconds, 0)
        let minutes = Int(clampedSeconds / 60)
        let remainingSeconds = clampedSeconds - Double(minutes * 60)
        return String(format: "%02d:%06.3f", minutes, remainingSeconds)
    }

    private func firstFCPXMLTitleLine(_ text: String, fallback: String) -> String {
        let line = text.components(separatedBy: .newlines).first ?? text
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        return trimmed.count <= 64 ? trimmed : String(trimmed.prefix(64))
    }

    private func fcpxmlTitlePosition(_ style: SubtitleStyle) -> (x: String, y: String, z: String) {
        (
            formatFCPXMLNumber(style.positionX),
            formatFCPXMLNumber(style.positionY),
            formatFCPXMLNumber(style.positionZ)
        )
    }

    private func fcpxmlTextStyleAttributes(_ style: SubtitleStyle) -> String {
        let fontFace: String
        switch style.fontWeight {
        case .regular:
            fontFace = "Regular"
        case .medium:
            fontFace = "Medium"
        case .semibold:
            fontFace = "Semibold"
        case .bold:
            fontFace = "Bold"
        }

        let alignment: String
        switch style.horizontalAlignment {
        case .leading:
            alignment = "left"
        case .center:
            alignment = "center"
        case .trailing:
            alignment = "right"
        }

        let strokeColor: String
        let strokeWidth: String
        if style.outlineEnabled {
            strokeColor = fcpxmlColor(style.outlineColorHex, alpha: style.outlineOpacity)
            strokeWidth = formatFCPXMLNumber(-max(style.outlineWidth, 0.5))
        } else if style.surfaceEnabled {
            strokeColor = fcpxmlColor(style.surfaceColorHex, alpha: style.surfaceOpacity)
            strokeWidth = formatFCPXMLNumber(-max(8, style.fontSize * 0.18))
        } else {
            strokeColor = fcpxmlColor("#000000", alpha: 0)
            strokeWidth = "0"
        }

        return """
        font="\(escapeXML(style.fontFamily))" fontSize="\(formatFCPXMLNumber(style.fontSize))" fontFace="\(fontFace)" fontColor="\(fcpxmlColor(style.fontColorHex))" strokeColor="\(strokeColor)" strokeWidth="\(strokeWidth)" alignment="\(alignment)"
        """
    }

    private func fcpxmlColor(_ hex: String, alpha: Double = 1) -> String {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = Int(trimmed, radix: 16) ?? 0
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255

        return [
            formatFCPXMLNumber(red),
            formatFCPXMLNumber(green),
            formatFCPXMLNumber(blue),
            formatFCPXMLNumber(max(0, min(alpha, 1)))
        ].joined(separator: " ")
    }

    private func formatFCPXMLNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }

        return String(format: "%.4f", value)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }

    private func importIntoFinalCutPro(_ fcpxmlURL: URL) throws {
        let attempts: [[String]] = [
            ["-b", "com.apple.FinalCutApp", fcpxmlURL.path],
            ["-b", "com.apple.FinalCut", fcpxmlURL.path]
        ] + finalCutProApplicationURLs().map { ["-a", $0.path, fcpxmlURL.path] } + [
            [fcpxmlURL.path]
        ]

        var failureMessages: [String] = []
        for arguments in attempts {
            do {
                try runOpenCommand(arguments: arguments)
                return
            } catch {
                failureMessages.append(error.localizedDescription)
            }
        }

        throw NSError(
            domain: "SubForge.FinalCutProImport",
            code: 2,
            userInfo: [
                NSLocalizedDescriptionKey: failureMessages.last
                    ?? "无法发现 Final Cut Pro 或打开 FCPXML。"
            ]
        )
    }

    private func finalCutProApplicationURLs() -> [URL] {
        let workspace = NSWorkspace.shared
        let bundleURLs = [
            workspace.urlForApplication(withBundleIdentifier: "com.apple.FinalCutApp"),
            workspace.urlForApplication(withBundleIdentifier: "com.apple.FinalCut")
        ].compactMap(\.self)

        let pathURLs = [
            "/Applications/Final Cut Pro Creator Studio.app",
            "/Applications/Final Cut Pro.app"
        ].map { URL(fileURLWithPath: $0, isDirectory: true) }

        var seen = Set<String>()
        return (bundleURLs + pathURLs).filter { url in
            guard FileManager.default.fileExists(atPath: url.path) else { return false }
            return seen.insert(url.standardizedFileURL.path).inserted
        }
    }

    private func runOpenCommand(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments

        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(
                domain: "SubForge.FinalCutProImport",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message?.isEmpty == false ? message! : "无法打开 Final Cut Pro 或导入 FCPXML。"]
            )
        }
    }

    private func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

}
