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
    @Published var settings: AppSettings = SettingsStore.load()
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
    private var waveformTask: Task<Void, Never>?
    @Published private(set) var editorFocusContext: EditorFocusContext = .none

    init() {
        let initialSettings = SettingsStore.load()
        settings = initialSettings
        pipelineStages = Self.makePipelineStages(proofreadingEnabled: initialSettings.proofreadingEnabled)

        $settings
            .dropFirst()
            .sink { [weak self] settings in
                SettingsStore.save(settings)
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
            syncWatchState()
            return
        }

        AppLog.watcher.info("watch apply settings path=\(path, privacy: .public)")
        watchFolderService.start(watching: URL(fileURLWithPath: path, isDirectory: true))
        syncWatchState()
    }

    private func syncWatchState() {
        isWatchingDirectory = watchFolderService.isWatching
        watchStatusMessage = watchFolderService.statusMessage
        watchedFileCount = watchFolderService.processedCount
    }

    private func handleDetectedFCPAudio(_ url: URL) -> Bool {
        guard pipelineTask == nil else {
            AppLog.watcher.info("watch detected \(url.lastPathComponent, privacy: .public), but pipeline is busy")
            return false
        }

        AppLog.watcher.info("watch accepted FCP audio \(url.path, privacy: .public)")
        activateAppForWatchedFile()
        showToast("监听到 FCP 音频：\(url.lastPathComponent)", level: .info)
        importDocument(at: url)
        return true
    }

    private func activateAppForWatchedFile() {
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
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

                let provider = TranscriptionService.createProvider(settings: self.settings)
                let engineName = self.settings.transcriptionEngine.rawValue
                self.markStageActive(.transcribe, progress: 0.36, message: "正在使用 \(engineName) 转写…")
                var transcribedSegments = try await provider.transcribe(audioURL: url, language: self.settings.language)
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
            guard let directory = chooseExportDirectory() else { return }

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

    private func chooseExportDirectory() -> URL? {
        switch settings.exportSettings.saveLocation {
        case .sameAsSource:
            if let directory = currentDocumentURL?.deletingLastPathComponent() {
                return directory
            }
            return askForExportDirectory()
        case .customFolder:
            let path = settings.exportSettings.customOutputPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            return askForExportDirectory()
        }
    }

    private func askForExportDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "导出到此处"
        panel.message = "选择导出目录"

        guard panel.runModal() == .OK else { return nil }
        return panel.url
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
        let totalDuration = fcpxmlTime(max(playbackDuration, segments.last?.end ?? 1), fps: fps, minimumFrames: 1)
        let titleStart = "0s"

        let titles = segments.enumerated().compactMap { index, segment -> String? in
            let duration = max(segment.end - segment.start, 0.1)
            guard duration > 0 else { return nil }

            let textStyleID = "ts\(index + 1)"
            let name = escapeXML(firstFCPXMLTitleLine(segment.text, fallback: "Caption \(index + 1)"))
            let offset = fcpxmlTime(segment.start, fps: fps)
            let titleDuration = fcpxmlTime(duration, fps: fps, minimumFrames: 1)
            let position = fcpxmlTitlePosition(style)
            let styleAttributes = fcpxmlTextStyleAttributes(style)

            return """
                                <title ref="r2" offset="\(offset)" name="\(name)" duration="\(titleDuration)" start="\(titleStart)">
                                  <param name="Position" key="9999/10199/10201/1/100/101" value="\(position.x) \(position.y) \(position.z)"/>
                                  <param name="Alignment" key="9999/10199/10201/2/354/1002961760/401" value="1 (Center)"/>
                                  <param name="Alignment" key="9999/10199/10201/2/373" value="0 (Left) 2 (Bottom)"/>
                                  <text>
                                    <text-style ref="\(textStyleID)">\(escapeXML(segment.text))</text-style>
                                  </text>
                                  <text-style-def id="\(textStyleID)">
                                    <text-style \(styleAttributes)/>
                                  </text-style-def>
                                </title>
            """
        }.joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE fcpxml>
        <fcpxml version="1.9">
          <resources>
            <format id="r1" name="\(format.name)" frameDuration="1/\(fps)s" width="\(format.width)" height="\(format.height)" colorSpace="1-1-1 (Rec. 709)"/>
            <effect id="r2" name="Custom" uid=".../Titles.localized/Build In:Out.localized/Custom.localized/Custom.moti"/>
          </resources>
          <library>
            <event name="SubForge Export">
              <project name="\(escapeXML(projectName))">
                <sequence format="r1" tcStart="0s" tcFormat="NDF" duration="\(totalDuration)" audioLayout="stereo" audioRate="48k">
                  <spine>
        \(titles)
                  </spine>
                </sequence>
              </project>
            </event>
          </library>
        </fcpxml>
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
        return "\(frames)/\(fps)s"
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
        let escapedPath = escapeAppleScriptString(fcpxmlURL.path)
        let source = """
        tell application "Final Cut Pro"
            activate
            open POSIX file "\(escapedPath)"
        end tell
        """

        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw NSError(
                domain: "SubForge.FinalCutProImport",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "无法创建 Final Cut Pro 导入脚本。"]
            )
        }

        script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String
                ?? "无法打开 Final Cut Pro 或导入 FCPXML。"
            throw NSError(
                domain: "SubForge.FinalCutProImport",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }

    private func escapeAppleScriptString(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
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
