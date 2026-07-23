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
    case failed
}

struct PipelineStageState: Identifiable {
    let stage: PipelineStage
    let title: String
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
    static let supportedAudioExtensions: Set<String> = ["m4a", "mp3", "wav", "aac", "aif", "aiff"]
    static let supportedSubtitleExtensions: Set<String> = ["srt"]
    static let supportedImportExtensions = supportedAudioExtensions.union(supportedSubtitleExtensions)

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
    @Published var capturedTimestamp = ""
    @Published var activeEditorSurface: EditorSurface = .table
    @Published var showInspector = true
    @Published var isShortcutGuidePresented = false
    @Published var toast: ToastMessage?
    @Published var isWatchingDirectory = false
    @Published var watchStatusMessage = "未启动"
    @Published var watchedFileCount = 0
    let smartService = SmartServiceStore()
    var settingsWindowPresenter: (() -> Void)?

    var cancellables = Set<AnyCancellable>()
    var playbackTimer: Timer?
    var pipelineTask: Task<Void, Never>?
    var funASRHeartbeatObserver: NSObjectProtocol?
    /// 当前导入音频的安全作用域，必须在整次转写流水线期间持有。
    var currentDocumentAccess: SecurityScopedResourceAccess?
    /// 播放/波形用的沙箱内可读副本（外部文件在 App Sandbox 下 AVPlayer 常读不到原路径）。
    var playbackLocalMedia: SandboxMediaAccess.PreparedFile?
    let playbackService = MediaPlaybackService()
    let keyboardMonitor = EditorKeyboardMonitor()
    let watchFolderService = WatchFolderService()
    let menuBarController = MenuBarController()
    var watchDirectoryAccess: SecurityScopedResourceAccess?
    var waveformTask: Task<Void, Never>?
    /// 整条流水线计时（准备 → 转写 → 校对），从点开始就走秒表。
    var pipelineStartedAt: Date?
    var pipelineTickerTask: Task<Void, Never>?
    var pipelineModelLabel = ""
    var pipelinePhaseLabel = "准备中"
    var pipelineUsesLocalEngine = false
    var pipelineAudioDuration: TimeInterval = 0
    @Published var editorFocusContext: EditorFocusContext = .none

    init() {
        let initialSettings = SettingsStore.load()
        settings = initialSettings
        pipelineStages = Self.makePipelineStages(
            proofreadingEnabled: initialSettings.shouldRunProofreading,
            officialSmart: initialSettings.transcriptionEngine == .officialSmart
        )
        menuBarController.bind(model: self)
        SubForgeAppDelegate.applyActivationPolicy(for: initialSettings)
        menuBarController.setVisible(initialSettings.showMenuBarIcon)
        MainWindowController.shared.setHidesDockOnClose(initialSettings.showMenuBarIcon)

        $settings
            .dropFirst()
            .sink { [weak self] settings in
                guard let self else { return }
                SettingsStore.save(settings)
                SubForgeAppDelegate.applyActivationPolicy(for: settings)
                MainWindowController.shared.setHidesDockOnClose(settings.showMenuBarIcon)
                self.menuBarController.setVisible(settings.showMenuBarIcon)
                self.menuBarController.refreshMenu()
                self.applyWatchSettings(settings)
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

        playbackService.onLoadFailed = { message in
            // 转写进行中不打扰；进入编辑后点播放时再提示更清晰。
            AppLog.editor.error("media load failed message=\(message, privacy: .public)")
        }

        keyboardMonitor.start { [weak self] event in
            self?.handleEditorKeyDown(event) ?? false
        }

        bindWatchFolderService()
        applyWatchSettings(initialSettings)
        funASRHeartbeatObserver = NotificationCenter.default.addObserver(
            forName: .funASRTranscriptionHeartbeat,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            Task { @MainActor in
                self.handleFunASRHeartbeat(notification)
            }
        }

        Task { [weak self] in
            guard let self else { return }
            await self.smartService.reconcilePurchasesAtLaunch()
        }
    }

    deinit {
        playbackTimer?.invalidate()
        pipelineTask?.cancel()
        waveformTask?.cancel()
        watchFolderService.stop()
        if let funASRHeartbeatObserver {
            NotificationCenter.default.removeObserver(funASRHeartbeatObserver)
        }
    }
}
