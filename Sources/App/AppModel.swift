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

    private var cancellables = Set<AnyCancellable>()
    private var playbackTimer: Timer?
    private var pipelineTask: Task<Void, Never>?
    private let playbackService = MediaPlaybackService()
    private let keyboardMonitor = EditorKeyboardMonitor()
    private var waveformTask: Task<Void, Never>?
    @Published private(set) var editorFocusContext: EditorFocusContext = .none

    init() {
        let initialSettings = SettingsStore.load()
        settings = initialSettings
        pipelineStages = Self.makePipelineStages(proofreadingEnabled: initialSettings.proofreadingEnabled)

        $settings
            .dropFirst()
            .sink { SettingsStore.save($0) }
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
    }

    deinit {
        playbackTimer?.invalidate()
        pipelineTask?.cancel()
        waveformTask?.cancel()
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

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "导出到此处"
        panel.message = "选择导出目录"

        guard panel.runModal() == .OK, let directory = panel.url else { return }

        let baseName = currentDocumentURL?.deletingPathExtension().lastPathComponent ?? "SubForge Export"
        let srtURL = directory.appendingPathComponent(baseName).appendingPathExtension("srt")
        let fcpxmlURL = directory.appendingPathComponent(baseName).appendingPathExtension("fcpxml")

        do {
            try SRTCodec.generate(segments).write(to: srtURL, atomically: true, encoding: .utf8)
            try makeFCPXML(projectName: baseName, segments: segments).write(to: fcpxmlURL, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([srtURL, fcpxmlURL])
            showToast("已导出 SRT 和 FCPXML", level: .success)
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

    private func makeFCPXML(projectName: String, segments: [SubtitleSegment]) -> String {
        let titles = segments.enumerated().map { index, segment in
            """
                  <title lane="1" offset="\(segment.start)s" duration="\(max(segment.end - segment.start, 0.1))s" ref="r2" name="Caption \(index + 1)">
                    <text>
                      <text-style ref="ts1">\(escapeXML(segment.text))</text-style>
                    </text>
                  </title>
            """
        }.joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <fcpxml version="1.10">
          <resources>
            <format id="r1" name="FFVideoFormat1080p30" frameDuration="1/30s" width="1920" height="1080"/>
            <effect id="r2" name="Basic Title" uid=".../Titles.localized/Bumper:Opener.localized/Basic Title.localized/Basic Title.moti"/>
            <text-style-def id="ts1"/>
          </resources>
          <library>
            <event name="SubForge Export">
              <project name="\(escapeXML(projectName))">
                <sequence format="r1" duration="\(max(playbackDuration, segments.last?.end ?? 1))s">
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

    private func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

}
