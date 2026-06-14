import SwiftUI

/// 播放控制栏
struct TransportBar: View {
    @ObservedObject var audioService: AudioPlayerService
    @EnvironmentObject var appState: AppState

    @State private var isDragging = false
    @State private var dragProgress: Double = 0

    private var hasAudio: Bool {
        guard let url = appState.audioFileURL else { return false }
        let ext = url.pathExtension.lowercased()
        return ext != "srt" && ext != "txt"
    }

    var body: some View {
        VStack(spacing: 0) {
            // 进度条（仅音频模式）
            if hasAudio {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.15))
                            .frame(height: 6)

                        Rectangle()
                            .fill(Color.blue)
                            .frame(width: geo.size.width * progress, height: 6)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isDragging = true
                                dragProgress = max(0, min(1, value.location.x / geo.size.width))
                            }
                            .onEnded { _ in
                                isDragging = false
                                audioService.seek(to: dragProgress * audioService.duration)
                            }
                    )
                }
                .frame(height: 6)
                .padding(.horizontal, 20)
            }

            // 控制栏
            HStack(spacing: 16) {
                // 播放/暂停（仅音频模式）
                if hasAudio {
                    Button(action: {
                        if audioService.isPlaying {
                            audioService.pause()
                            appState.copyCurrentTimestamp()
                        } else {
                            audioService.play()
                        }
                    }) {
                        Image(systemName: audioService.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18))
                    }
                    .buttonStyle(.borderless)

                    // 时间
                    Text(formatTime(audioService.currentTime))
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("/")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                    Text(formatTime(audioService.duration))
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Spacer()

                    // 倍速
                    Text("倍速 \(String(format: "%.2g", audioService.playbackRate))x")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    // SRT 模式：显示文件名
                    if let url = appState.audioFileURL {
                        Text("📄 \(url.lastPathComponent)")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                // 保存
                Button(action: {
                    appState.saveSRT()
                }) {
                    HStack(spacing: 4) {
                        Text("保存 SRT")
                        if appState.isDirty {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 6, height: 6)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!appState.canSave)

                // 导出
                Menu {
                    Button("导出 SRT") { exportSRT() }
                    Button("导出 FCPXML") { exportFCPXML() }
                } label: {
                    Label("导出", systemImage: "square.and.arrow.up")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    private var progress: Double {
        if isDragging { return dragProgress }
        guard audioService.duration > 0 else { return 0 }
        return audioService.currentTime / audioService.duration
    }

    private func exportSRT() {
        guard let audioURL = appState.audioFileURL else { return }
        let outputURL = appState.settings.resolveOutputURL(for: audioURL, extension: "srt")
        let content = SRTParser.generate(appState.segments)
        do {
            try content.write(to: outputURL, atomically: true, encoding: .utf8)
            appState.showToast("SRT 已导出：\(outputURL.lastPathComponent)", type: .success)
            NSWorkspace.shared.activateFileViewerSelecting([outputURL])
        } catch {
            appState.showToast("导出失败：\(error.localizedDescription)", type: .error)
        }
    }

    private func exportFCPXML() {
        guard let audioURL = appState.audioFileURL else { return }
        let outputURL = appState.settings.resolveOutputURL(for: audioURL, extension: "fcpxml")

        // 自动查找同目录下的 .fcpbundle
        let bundlePath = FCPXMLGenerator.findFCPBundle(in: audioURL.deletingLastPathComponent())

        let xml = FCPXMLGenerator.generate(
            segments: appState.segments,
            projectName: audioURL.deletingPathExtension().lastPathComponent,
            fps: appState.settings.exportSettings.fps,
            width: appState.settings.exportSettings.width,
            height: appState.settings.exportSettings.height,
            style: appState.settings.subtitleStyle,
            bundlePath: bundlePath
        )
        do {
            try xml.write(to: outputURL, atomically: true, encoding: .utf8)
            let bundleInfo = bundlePath.map { " → \($0.lastPathComponent)" } ?? ""
            appState.showToast("FCPXML 已导出\(bundleInfo)", type: .success)
            // 直接在 Final Cut Pro 中打开
            NSWorkspace.shared.open(outputURL)
        } catch {
            appState.showToast("导出失败：\(error.localizedDescription)", type: .error)
        }
    }
}

// MARK: - AppSettings 输出路径解析
extension AppSettings {
    func resolveOutputURL(for audioURL: URL, extension ext: String) -> URL {
        let baseName = audioURL.deletingPathExtension().lastPathComponent
        switch exportSettings.saveLocation {
        case .sameAsAudio:
            return audioURL.deletingPathExtension().appendingPathExtension(ext)
        case .custom:
            let dir = URL(fileURLWithPath: exportSettings.customOutputPath.isEmpty
                          ? audioURL.deletingLastPathComponent().path
                          : exportSettings.customOutputPath)
            return dir.appendingPathComponent(baseName).appendingPathExtension(ext)
        }
    }
}
