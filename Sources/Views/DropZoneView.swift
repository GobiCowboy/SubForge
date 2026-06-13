import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

/// 首页
struct DropZoneView: View {
    @EnvironmentObject var appState: AppState
    @State private var isDragOver = false
    @State private var showFilePicker = false
    @State private var showSettings = false
    @State private var recentFiles: [RecentFile] = []

    private let supportedTypes: [UTType] = [
        .audio,
        .movie,
        UTType(filenameExtension: "m4a") ?? .audio,
        UTType(filenameExtension: "mp3") ?? .audio,
        UTType(filenameExtension: "wav") ?? .audio,
        UTType(filenameExtension: "aac") ?? .audio,
        UTType(filenameExtension: "srt") ?? .plainText,
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(maxHeight: 60)

            HStack(alignment: .top, spacing: 0) {
                // 左侧：品牌 + 操作（紧凑）
                VStack(spacing: 14) {
                    Spacer()
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(isDragOver ? .blue : .accentColor)

                    Text("SubForge")
                        .font(.system(size: 22, weight: .bold, design: .rounded))

                    Text("字幕生成 · 编辑 · 导出")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("打开文件") {
                        showFilePicker = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Text("或拖入音频 / SRT")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(width: 220)
                .padding(.vertical, 30)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isDragOver ? Color.blue.opacity(0.06) : Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                        .foregroundStyle(isDragOver ? Color.blue : Color.secondary.opacity(0.2))
                )

                // 间距
                Spacer()
                    .frame(width: 50)

                // 右侧：最近项目（大区域）
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("最近项目")
                            .font(.title3.weight(.semibold))
                        Spacer()
                        Text("\(recentFiles.count) 个项目")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.bottom, 14)

                    Divider()

                    if recentFiles.isEmpty {
                        VStack(spacing: 10) {
                            Spacer()
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 36))
                                .foregroundStyle(.tertiary)
                            Text("暂无历史记录")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 1) {
                                ForEach(recentFiles) { file in
                                    RecentFileRow(file: file) {
                                        openRecentFile(file)
                                    }
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                )
            }
            .padding(.horizontal, 40)
            .frame(maxHeight: 400)

            Spacer()
                .frame(maxHeight: 40)

            // 底部状态栏（醒目）
            HStack(spacing: 20) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.green)
                        .frame(width: 7, height: 7)
                    Text(appState.settings.transcriptionEngine.rawValue)
                        .fontWeight(.medium)
                }

                Divider()
                    .frame(height: 16)

                HStack(spacing: 6) {
                    Image(systemName: appState.settings.proofreadingEnabled ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(appState.settings.proofreadingEnabled ? .green : .secondary)
                    Text("AI校对")
                    if appState.settings.proofreadingEnabled {
                        Text("(\(appState.settings.proofreadingEngine.rawValue))")
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()
                    .frame(height: 16)

                Label(appState.settings.language == "zh-CN" ? "中文" : appState.settings.language, systemImage: "globe")

                Spacer()

                Button {
                    showSettings = true
                } label: {
                    Label("设置", systemImage: "gear")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(.bar)

            Spacer()
                .frame(height: 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers)
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: supportedTypes,
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                handleFile(url)
            }
        }
        .onAppear {
            loadRecentFiles()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(appState)
        }
    }

    // MARK: - 最近项目

    private func loadRecentFiles() {
        recentFiles = RecentFileManager.load()
    }

    private func addRecentFile(_ url: URL, type: String, subtitleCount: Int) {
        RecentFileManager.add(url: url, type: type, subtitleCount: subtitleCount)
        recentFiles = RecentFileManager.load()
    }

    private func openRecentFile(_ file: RecentFile) {
        let url = URL(fileURLWithPath: file.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            appState.showToast("文件已不存在：\(file.name)", type: .error)
            RecentFileManager.remove(path: file.path)
            recentFiles = RecentFileManager.load()
            return
        }
        handleFile(url)
    }

    // MARK: - 文件处理

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in
                handleFile(url)
            }
        }
        return true
    }

    private func handleFile(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            appState.showToast("文件不存在：\(url.lastPathComponent)", type: .error)
            return
        }

        let ext = url.pathExtension.lowercased()

        if ext == "srt" {
            loadSRTFile(url: url)
        } else {
            appState.loadAudioFile(url: url)
            Task {
                await performTranscription(url: url)
            }
        }
    }

    private func loadSRTFile(url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let segments = SRTParser.parse(content)
            guard !segments.isEmpty else {
                appState.showToast("SRT 文件为空或格式无法解析", type: .error)
                return
            }
            appState.audioFileURL = url
            appState.setSegments(segments)
            appState.showToast("已导入 \(segments.count) 条字幕", type: .success)
        } catch {
            appState.showToast("读取 SRT 失败：\(error.localizedDescription)", type: .error)
        }
    }

    private func performTranscription(url: URL) async {
        appState.isTranscribing = true
        appState.transcriptionStep = .running
        appState.proofreadingStep = .pending
        appState.pipelineProgress = 0.1

        let settings = appState.settings
        let engineName = settings.transcriptionEngine.rawValue
        let audioDuration = getAudioDuration(url: url)
        let durationStr = audioDuration.map { String(format: "%.1f秒", $0) } ?? "未知"

        // Step 1: 转写
        appState.transcriptionProgress = "正在使用 \(engineName) 转写（音频 \(durationStr)）..."

        let provider = TranscriptionService.createProvider(settings: settings)
        let startTime = Date()

        do {
            let segments = try await provider.transcribe(audioURL: url, language: settings.language)
            let elapsed = Date().timeIntervalSince(startTime)
            let speedStr = audioDuration.map { d in String(format: "%.1fx", d / elapsed) } ?? ""

            appState.setSegments(segments)
            appState.transcriptionStep = .done
            appState.pipelineProgress = 0.5

            // Step 2: AI 校对（如果启用）
            if settings.proofreadingEnabled, let proofProvider = ProofreadingService.createProvider(settings: settings) {
                let proofEngine = settings.proofreadingEngine.rawValue
                appState.proofreadingStep = .running
                appState.transcriptionProgress = "转写完成（\(speedStr)），正在使用 \(proofEngine) 校对..."

                do {
                    // 分离空白字幕和有内容的字幕
                    let blankPrefix = appState.segments.first?.text.isEmpty == true ? [appState.segments.first!] : []
                    let contentSegments = blankPrefix.isEmpty ? appState.segments : Array(appState.segments.dropFirst())

                    // 只校对有内容的字幕
                    let corrected = try await proofProvider.proofread(segments: contentSegments, batchSize: 20)
                    let diffCount = zip(contentSegments, corrected).filter { $0.0.text != $0.1.text }.count

                    // 合回空白字幕 + 校对后的字幕
                    let merged = blankPrefix + corrected
                    appState.setSegments(merged)
                    appState.proofreadingStep = .done
                    appState.pipelineProgress = 1.0
                    appState.showToast(
                        "✅ \(engineName) 转写完成（\(speedStr)）→ \(proofEngine) 校对完成，修正 \(diffCount) 处",
                        type: .success
                    )
                } catch {
                    appState.proofreadingStep = .done
                    appState.pipelineProgress = 1.0
                    appState.showToast(
                        "✅ \(engineName) 转写完成（\(speedStr)）→ 校对失败：\(error.localizedDescription)",
                        type: .error
                    )
                }
            } else {
                appState.pipelineProgress = 1.0
                appState.showToast(
                    "✅ \(engineName) 转写完成：\(segments.count) 条字幕，\(speedStr)",
                    type: .success
                )
            }
        } catch {
            let elapsed = Date().timeIntervalSince(startTime)
            appState.showToast("❌ \(engineName) 转写失败（\(String(format: "%.1f", elapsed))s）：\(error.localizedDescription)", type: .error)
        }
        appState.isTranscribing = false
        appState.transcriptionProgress = ""
    }

    private func getAudioDuration(url: URL) -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        let duration = asset.duration
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isNaN ? nil : seconds
    }
}

// MARK: - 最近文件行

struct RecentFileRow: View {
    let file: RecentFile
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: file.type == "srt" ? "doc.text" : "waveform")
                    .font(.system(size: 18))
                    .foregroundStyle(.blue)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text("\(file.subtitleCount) 条字幕")
                        Text("·")
                        Text(file.timeAgo)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - 最近文件管理

struct RecentFile: Identifiable, Codable {
    var id: String { path }
    let path: String
    let name: String
    let type: String      // "audio" or "srt"
    let subtitleCount: Int
    let timestamp: TimeInterval

    var timeAgo: String {
        let interval = Date().timeIntervalSince1970 - timestamp
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600)) 小时前" }
        return "\(Int(interval / 86400)) 天前"
    }
}

enum RecentFileManager {
    private static let key = "recentFiles"
    private static let maxCount = 20

    static func load() -> [RecentFile] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let files = try? JSONDecoder().decode([RecentFile].self, from: data) else {
            return []
        }
        return files
    }

    static func add(url: URL, type: String, subtitleCount: Int) {
        var files = load()
        // 去重
        files.removeAll { $0.path == url.path }
        let file = RecentFile(
            path: url.path,
            name: url.lastPathComponent,
            type: type,
            subtitleCount: subtitleCount,
            timestamp: Date().timeIntervalSince1970
        )
        files.insert(file, at: 0)
        if files.count > maxCount {
            files = Array(files.prefix(maxCount))
        }
        if let data = try? JSONEncoder().encode(files) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func remove(path: String) {
        var files = load()
        files.removeAll { $0.path == path }
        if let data = try? JSONEncoder().encode(files) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - 通知名称
extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
}
