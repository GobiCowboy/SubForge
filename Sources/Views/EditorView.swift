import SwiftUI

/// 编辑器主视图
struct EditorView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var audioService = AudioPlayerService()
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // 顶部控制栏
            TransportBar(audioService: audioService)

            // 字幕列表
            subtitleList

            // 底部状态栏
            statusBar
        }
        .onAppear {
            setupAudio()
            setupKeyboard()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(appState)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            showSettings = true
        }
    }

    // MARK: - 字幕列表

    private var subtitleList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(appState.segments.enumerated()), id: \.element.id) { index, segment in
                        SubtitleCardView(
                            segment: segment,
                            index: index,
                            isActive: index == appState.activeIndex,
                            onTap: {
                                audioService.seek(to: segment.start)
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onChange(of: appState.activeIndex) { _, newIndex in
                if newIndex >= 0 && newIndex < appState.segments.count {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(appState.segments[newIndex].id, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - 状态栏

    private var statusBar: some View {
        HStack(spacing: 12) {
            Button {
                appState.reset()
            } label: {
                Label("首页", systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)
            .font(.caption)

            Divider()
                .frame(height: 14)

            if let url = appState.audioFileURL {
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text("\(appState.segments.count) 条字幕")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("设置") {
                showSettings = true
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - 音频设置

    private var hasAudio: Bool {
        guard let url = appState.audioFileURL else { return false }
        let ext = url.pathExtension.lowercased()
        return ext != "srt" && ext != "txt"
    }

    private func setupAudio() {
        guard hasAudio, let url = appState.audioFileURL else { return }
        do {
            try audioService.load(url: url)
            appState.duration = audioService.duration
            audioService.onTimeUpdate = { time in
                appState.currentTime = time
                updateActiveIndex(for: time)
            }
            // 同步播放速率
            audioService.setRate(appState.playbackRate)
        } catch {
            appState.showToast("音频加载失败：\(error.localizedDescription)", type: .error)
        }
    }

    private func updateActiveIndex(for time: TimeInterval) {
        let segments = appState.segments
        var newIdx = -1
        for (i, seg) in segments.enumerated() {
            // 跳过空白字幕（开头的占位字幕）
            if seg.text.isEmpty { continue }
            if time >= seg.start && time < seg.end {
                newIdx = i
                break
            }
        }
        // 如果超过最后一条（且最后一条非空）
        if newIdx == -1, let last = segments.last, !last.text.isEmpty, time >= last.end {
            newIdx = segments.count - 1
        }
        if newIdx != appState.activeIndex {
            appState.activeIndex = newIdx
        }
    }

    // MARK: - 键盘快捷键

    private func setupKeyboard() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyEvent(event)
        }
    }

    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        let isEditing = appState.editingIndex != nil || NSApp.keyWindow?.firstResponder is NSTextView

        // 编辑状态下，只处理 Escape
        if isEditing {
            if event.keyCode == 53 { // Escape
                appState.editingIndex = nil
                NSApp.keyWindow?.makeFirstResponder(nil)
                return nil
            }
            return event // 其他键正常传递给编辑器
        }

        // 非编辑状态的快捷键
        switch event.keyCode {
        case 49: // Space
            if audioService.isPlaying {
                audioService.pause()
                appState.currentTime = audioService.currentTime
                appState.copyCurrentTimestamp()
            } else {
                audioService.play()
            }
            return nil

            case 38: // J - 降速
                let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                if let idx = speeds.firstIndex(of: audioService.playbackRate), idx > 0 {
                    audioService.setRate(speeds[idx - 1])
                    appState.showToast("倍速 \(speeds[idx - 1])x", type: .info)
                }
                return nil

            case 37: // L - 加速
                let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                if let idx = speeds.firstIndex(of: audioService.playbackRate), idx < speeds.count - 1 {
                    audioService.setRate(speeds[idx + 1])
                    appState.showToast("倍速 \(speeds[idx + 1])x", type: .info)
                }
                return nil

            case 36: // Enter - 进入编辑
                if appState.activeIndex >= 0 {
                    NotificationCenter.default.post(
                        name: .enterEditMode,
                        object: nil,
                        userInfo: ["index": appState.activeIndex]
                    )
                }
                return nil

            case 126: // Arrow Up
                navigateSubtitle(direction: -1)
                return nil

            case 125: // Arrow Down
                navigateSubtitle(direction: 1)
                return nil

            default:
                break
            }

        return event
    }

    private func navigateSubtitle(direction: Int) {
        let newIdx = appState.activeIndex + direction
        guard newIdx >= 0, newIdx < appState.segments.count else { return }
        appState.activeIndex = newIdx
        audioService.seek(to: appState.segments[newIdx].start)
    }
}

// MARK: - 通知
extension Notification.Name {
    static let enterEditMode = Notification.Name("enterEditMode")
}
