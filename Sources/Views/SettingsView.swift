import SwiftUI
import AVFoundation

/// 设置页
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var settings: AppSettings = AppSettings()

    // 测试状态
    @State private var transcriptionTestResult: TranscriptionTestResult?
    @State private var isTestingTranscription = false
    @State private var llmTestResult: String?
    @State private var llmTestIsError = false
    @State private var isTestingLLM = false
    @State private var cloudASRTestResult: String?
    @State private var cloudASRTestIsError = false
    @State private var isTestingCloudASR = false
    // 音频播放
    @State private var testAudioPlayer: AVAudioPlayer?
    @State private var testAudioDelegate: AudioPlayDelegate?
    @State private var isPlayingTestAudio = false
    // 模型下载
    @State private var downloadingModel: WhisperModel?
    @State private var downloadProgress: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("设置").font(.title3.weight(.semibold))
                Spacer()
                Button("完成") {
                    appState.settings = settings
                    SettingsManager.save(settings)
                    dismiss()
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
            }
            .padding()

            ScrollView {
                VStack(spacing: 0) {
                    // ═══ 语音转写 ═══
                    GroupBox("语音转写") {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("引擎", selection: $settings.transcriptionEngine) {
                                ForEach(TranscriptionEngine.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.radioGroup)

                            Picker("语言", selection: $settings.language) {
                                Text("中文（简体）").tag("zh-CN")
                                Text("中文（繁体）").tag("zh-TW")
                                Text("英语").tag("en-US")
                                Text("日语").tag("ja-JP")
                                Text("韩语").tag("ko-KR")
                            }

                            // 本地 Whisper 模型管理
                            if settings.transcriptionEngine == .whisperLocal {
                                Divider()
                                Text("模型管理").font(.caption.bold()).foregroundStyle(.secondary)
                                ForEach(WhisperModel.allCases) { model in
                                    HStack(spacing: 10) {
                                        // 选中指示
                                        Image(systemName: settings.whisperModel == model ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(settings.whisperModel == model ? .blue : .secondary)
                                            .onTapGesture { settings.whisperModel = model }

                                        // 模型信息
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(model.displayName).font(.system(size: 13))
                                            if WhisperModelStore.isAvailable(model) {
                                                Text("已下载").font(.caption).foregroundStyle(.green)
                                            }
                                        }

                                        Spacer()

                                        // 下载按钮
                                        if !WhisperModelStore.isAvailable(model) {
                                            if downloadingModel == model {
                                                VStack(spacing: 4) {
                                                    ProgressView(value: downloadProgress)
                                                        .frame(width: 80)
                                                    Text("\(Int(downloadProgress * 100))%").font(.caption2).foregroundStyle(.secondary)
                                                }
                                            } else {
                                                Button("下载 (\(model.sizeMB)MB)") { downloadModel(model) }
                                                    .controlSize(.small)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }

                            Divider()

                            if settings.transcriptionEngine == .cloudASR {
                                Picker("服务商", selection: $settings.cloudASRPreset) {
                                    ForEach(CloudASRPreset.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                                }
                                .onChange(of: settings.cloudASRPreset) { _, p in
                                    settings.cloudASRURL = p.defaultURL
                                    settings.cloudASRModel = p.defaultModel
                                }
                                TextField("API 地址", text: $settings.cloudASRURL)
                                SecureField("API Key", text: $settings.cloudASRKey)
                                TextField("模型", text: $settings.cloudASRModel)
                            }

                            // 试听 + 测试
                            testAudioPlayButton
                            Button(action: {
                                switch settings.transcriptionEngine {
                                case .whisperLocal: testWhisperLocal()
                                case .appleSpeech: testAppleSpeech()
                                case .cloudASR: testCloudASR()
                                }
                            }) {
                                HStack(spacing: 6) {
                                    if isTestingTranscription || isTestingCloudASR { ProgressView().controlSize(.mini) }
                                    Text(isTestingTranscription || isTestingCloudASR ? "转写测试中..." : "🧪 测试转写")
                                }
                            }
                            .disabled(isTestingTranscription || isTestingCloudASR || (settings.transcriptionEngine == .cloudASR && settings.cloudASRKey.isEmpty))

                            if settings.transcriptionEngine == .whisperLocal, let r = transcriptionTestResult {
                                testResultBox(success: r.available, original: expectedASRText, recognized: r.message)
                            }
                            if settings.transcriptionEngine == .appleSpeech, let r = transcriptionTestResult {
                                testResultBox(success: r.available, original: expectedASRText, recognized: r.message)
                            }
                            if settings.transcriptionEngine == .cloudASR, let r = cloudASRTestResult {
                                testResultBox(success: !cloudASRTestIsError, original: expectedASRText, recognized: r)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .padding(.horizontal, 16).padding(.bottom, 12)

                    // ═══ AI 校对 ═══
                    GroupBox("AI 校对（可选）") {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("开启 AI 校对", isOn: $settings.proofreadingEnabled)
                            if settings.proofreadingEnabled {
                                Picker("引擎", selection: $settings.proofreadingEngine) {
                                    ForEach(ProofreadingEngine.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                                }
                                .pickerStyle(.radioGroup)

                                if settings.proofreadingEngine == .cloudLLM {
                                    Divider()
                                    Picker("服务商", selection: $settings.cloudLLMPreset) {
                                        ForEach(CloudLLMPreset.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                                    }
                                    .onChange(of: settings.cloudLLMPreset) { _, p in
                                        settings.cloudLLMURL = p.defaultURL
                                        settings.cloudLLMModel = p.defaultModel
                                    }
                                    TextField("API 地址", text: $settings.cloudLLMURL)
                                    SecureField("API Key", text: $settings.cloudLLMKey)
                                    TextField("模型", text: $settings.cloudLLMModel)

                                    Button(action: { testLLM() }) {
                                        HStack(spacing: 6) {
                                            if isTestingLLM { ProgressView().controlSize(.mini) }
                                            Text(isTestingLLM ? "校对测试中..." : "🧪 测试校对")
                                        }
                                    }
                                    .disabled(isTestingLLM || settings.cloudLLMKey.isEmpty)
                                    if let r = llmTestResult {
                                        testResultBox(success: !llmTestIsError, original: expectedLLMText, recognized: r)
                                    }
                                }
                                if settings.proofreadingEngine == .appleLocal {
                                    Button(action: { testAppleLLM() }) { Text("🧪 测试可用性") }
                                    if let r = llmTestResult {
                                        testResultBox(success: !llmTestIsError, original: "Apple Foundation Models", recognized: r)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .padding(.horizontal, 16).padding(.bottom, 12)

                    // ═══ 字幕样式 ═══
                    GroupBox("字幕样式") {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("字体", selection: $settings.subtitleStyle.fontFamily) {
                                Text("PingFang SC").tag("PingFang SC")
                                Text("Heiti SC").tag("Heiti SC")
                                Text("STHeiti").tag("STHeiti")
                                Text("Arial").tag("Arial")
                            }
                            Stepper("字号: \(settings.subtitleStyle.fontSize)", value: $settings.subtitleStyle.fontSize, in: 24...120, step: 4)
                            HStack(spacing: 16) {
                                HStack(spacing: 6) {
                                    Circle().fill(colorFromHex(settings.subtitleStyle.fontColor)).frame(width: 16, height: 16)
                                        .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                                    Text("字色"); ColorField(text: $settings.subtitleStyle.fontColor)
                                }
                                HStack(spacing: 6) {
                                    Circle().fill(colorFromHex(settings.subtitleStyle.outlineColor)).frame(width: 16, height: 16)
                                        .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                                    Text("描边色"); ColorField(text: $settings.subtitleStyle.outlineColor)
                                }
                            }
                            HStack { Text("描边宽度:"); TextField("", value: $settings.subtitleStyle.outlineWidth, format: .number).frame(width: 60) }
                            Picker("位置", selection: $settings.subtitleStyle.position) {
                                ForEach(SubtitlePosition.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.radioGroup)
                            Stepper("边距: \(settings.subtitleStyle.bottomMargin) px", value: $settings.subtitleStyle.bottomMargin, in: 0...200, step: 10)
                            Divider()
                            Stepper("每条字幕最长: \(settings.maxSubtitleLength == 0 ? "不限" : "\(settings.maxSubtitleLength) 字")", value: $settings.maxSubtitleLength, in: 0...100, step: 5)
                        }
                        .padding(.vertical, 4)
                    }
                    .padding(.horizontal, 16).padding(.bottom, 12)

                    // ═══ 输出设置 ═══
                    GroupBox("输出设置") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 20) {
                                Picker("帧率", selection: $settings.exportSettings.fps) {
                                    Text("24 fps").tag(24); Text("25 fps").tag(25); Text("30 fps").tag(30); Text("60 fps").tag(60)
                                }
                                Picker("分辨率", selection: resolutionBinding) {
                                    Text("1080p").tag(0); Text("4K").tag(1); Text("自定义").tag(2)
                                }
                            }
                            if resolutionBinding.wrappedValue == 2 {
                                HStack {
                                    TextField("宽", value: $settings.exportSettings.width, format: .number).frame(width: 80)
                                    Text("×")
                                    TextField("高", value: $settings.exportSettings.height, format: .number).frame(width: 80)
                                }
                            }
                            Picker("保存位置", selection: $settings.exportSettings.saveLocation) {
                                ForEach(SaveLocation.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                            if settings.exportSettings.saveLocation == .custom {
                                HStack { TextField("自定义路径", text: $settings.exportSettings.customOutputPath); Button("选择...") { selectOutputDirectory() } }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .padding(.horizontal, 16).padding(.bottom, 20)
                }
            }
        }
        .frame(width: 600, height: 700)
        .onAppear { settings = appState.settings }
    }

    // MARK: - 常量

    private let expectedASRText = "本视频耗时一年时间制作，共计一小时55min，58964字，带你认识进入社会学校不教但你要会的53个技能。视频均为主播原创实景拍摄。挑战一天学会一个新技能。"
    private let expectedLLMText = "今天天汽很好，我们去公圆玩吧"

    // MARK: - 试听按钮

    private var testAudioPlayButton: some View {
        Button(action: { toggleTestAudio() }) {
            HStack(spacing: 6) {
                Image(systemName: isPlayingTestAudio ? "stop.fill" : "play.fill")
                Text(isPlayingTestAudio ? "停止播放" : "🔊 试听测试音频")
            }
        }
    }

    // MARK: - 测试结果对比框

    @ViewBuilder
    private func testResultBox(success: Bool, original: String, recognized: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(success ? "测试通过" : "测试失败", systemImage: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.caption.bold()).foregroundStyle(success ? .green : .red)
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text(original).font(.caption).foregroundStyle(.secondary)
                Divider()
                Text("识别结果：").font(.caption.bold())
                Text(recognized).font(.caption).textSelection(.enabled)
            }
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - 播放测试音频

    private func toggleTestAudio() {
        if isPlayingTestAudio {
            testAudioPlayer?.stop(); isPlayingTestAudio = false
        } else {
            let url = testAudioURL()
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            do {
                testAudioPlayer = try AVAudioPlayer(contentsOf: url)
                let delegate = AudioPlayDelegate { isPlayingTestAudio = false }
                testAudioDelegate = delegate
                testAudioPlayer?.delegate = delegate
                testAudioPlayer?.play(); isPlayingTestAudio = true
            } catch {}
        }
    }

    private func testAudioURL() -> URL {
        // 优先：Bundle 内部的 Resources 目录
        if let bundled = Bundle.main.url(forResource: "test_audio", withExtension: "m4a") {
            return bundled
        }
        // 备选：app 同目录
        let dir = Bundle.main.bundleURL.deletingLastPathComponent()
        return dir.appendingPathComponent("test_audio.m4a")
    }

    // MARK: - 测试 Apple Speech

    private func testAppleSpeech() {
        isTestingTranscription = true; transcriptionTestResult = nil
        Task {
            let provider = AppleSpeechProvider()
            do {
                let segs = try await provider.transcribe(audioURL: testAudioURL(), language: settings.language)
                transcriptionTestResult = TranscriptionTestResult(available: true, message: segs.map { $0.text }.joined(separator: "\n"), duration: nil)
            } catch {
                transcriptionTestResult = TranscriptionTestResult(available: false, message: error.localizedDescription, duration: nil)
            }
            isTestingTranscription = false
        }
    }

    // MARK: - 测试本地 Whisper

    private func testWhisperLocal() {
        isTestingTranscription = true; transcriptionTestResult = nil
        Task {
            let provider = WhisperCppProvider()
            do {
                let segs = try await provider.transcribe(audioURL: testAudioURL(), language: settings.language)
                transcriptionTestResult = TranscriptionTestResult(available: true, message: segs.map { $0.text }.joined(separator: "\n"), duration: nil)
            } catch {
                transcriptionTestResult = TranscriptionTestResult(available: false, message: error.localizedDescription, duration: nil)
            }
            isTestingTranscription = false
        }
    }

    // MARK: - 测试云端 ASR

    private func testCloudASR() {
        isTestingCloudASR = true; cloudASRTestResult = nil
        Task {
            let provider = CloudASRProvider(apiURL: settings.effectiveASRURL, apiKey: settings.cloudASRKey, model: settings.effectiveASRModel)
            do {
                let segs = try await provider.transcribe(audioURL: testAudioURL(), language: settings.language)
                cloudASRTestResult = segs.map { $0.text }.joined(separator: "\n"); cloudASRTestIsError = false
            } catch {
                cloudASRTestResult = error.localizedDescription; cloudASRTestIsError = true
            }
            isTestingCloudASR = false
        }
    }

    // MARK: - 测试 LLM

    private func testLLM() {
        isTestingLLM = true; llmTestResult = nil
        Task {
            do {
                let corrected = try await CloudLLMProvider(apiURL: settings.effectiveLLMURL, apiKey: settings.cloudLLMKey, model: settings.effectiveLLMModel)
                    .proofread(segments: [SubtitleSegment(start: 0, end: 1, text: expectedLLMText)], batchSize: 1)
                llmTestResult = corrected.first?.text ?? ""; llmTestIsError = false
            } catch {
                llmTestResult = error.localizedDescription; llmTestIsError = true
            }
            isTestingLLM = false
        }
    }

    private func testAppleLLM() {
        if #available(macOS 26.0, *) {
            llmTestResult = "需要 Apple Intelligence 已启用"; llmTestIsError = false
        } else {
            llmTestResult = "需要 macOS 26+"; llmTestIsError = true
        }
    }

    // MARK: - 下载模型

    private func downloadModel(_ model: WhisperModel) {
        downloadingModel = model
        downloadProgress = 0

        Task {
            let url = URL(string: model.downloadURL)!
            let destination = WhisperModelStore.localPath(for: model)

            do {
                let (asyncBytes, response) = try await URLSession.shared.bytes(from: url)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    appState.showToast("下载失败：服务器错误", type: .error)
                    downloadingModel = nil
                    return
                }

                let totalBytes = httpResponse.expectedContentLength
                var data = Data()
                var receivedBytes: Int64 = 0

                for try await byte in asyncBytes {
                    data.append(byte)
                    receivedBytes += 1
                    if receivedBytes % 100000 == 0 && totalBytes > 0 {
                        downloadProgress = Double(receivedBytes) / Double(totalBytes)
                    }
                }

                try data.write(to: destination)
                downloadProgress = 1.0
                appState.showToast("\(model.rawValue) 模型下载完成", type: .success)

                // 自动选中刚下载的模型
                settings.whisperModel = model
            } catch {
                appState.showToast("下载失败：\(error.localizedDescription)", type: .error)
            }
            downloadingModel = nil
        }
    }

    // MARK: - 分辨率绑定

    private var resolutionBinding: Binding<Int> {
        Binding(
            get: {
                if settings.exportSettings.width == 1920 && settings.exportSettings.height == 1080 { return 0 }
                if settings.exportSettings.width == 3840 && settings.exportSettings.height == 2160 { return 1 }
                return 2
            },
            set: { v in
                switch v {
                case 0: settings.exportSettings.width = 1920; settings.exportSettings.height = 1080
                case 1: settings.exportSettings.width = 3840; settings.exportSettings.height = 2160
                default: break
                }
            }
        )
    }

    private func selectOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { settings.exportSettings.customOutputPath = url.path }
    }

    private func colorFromHex(_ hex: String) -> Color {
        let c = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard c.count == 6, let v = UInt64(c, radix: 16) else { return .gray }
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

// MARK: - 颜色字段

struct ColorField: View {
    @Binding var text: String
    var body: some View {
        TextField("#FFFFFF", text: $text).font(.system(size: 12, design: .monospaced)).frame(width: 80).textFieldStyle(.roundedBorder)
    }
}

// MARK: - 音频播放代理

class AudioPlayDelegate: NSObject, AVAudioPlayerDelegate {
    let onFinish: () -> Void
    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { onFinish() }
}

// MARK: - 设置持久化

enum SettingsManager {
    private static let key = "appSettings"
    static func save(_ s: AppSettings) { if let d = try? JSONEncoder().encode(s) { UserDefaults.standard.set(d, forKey: key) } }
    static func load() -> AppSettings {
        if let d = UserDefaults.standard.data(forKey: key), let s = try? JSONDecoder().decode(AppSettings.self, from: d) { return s }
        var s = AppSettings()
        if let c = loadConfigJSON() {
            if let a = c["cloudASR"] as? [String: String] {
                if let u = a["url"], !u.isEmpty { s.cloudASRURL = u }
                if let k = a["key"], !k.isEmpty { s.cloudASRKey = k }
                if let m = a["model"], !m.isEmpty { s.cloudASRModel = m }
            }
            if let l = c["cloudLLM"] as? [String: String] {
                if let u = l["url"], !u.isEmpty { s.cloudLLMURL = u }
                if let k = l["key"], !k.isEmpty { s.cloudLLMKey = k }
                if let m = l["model"], !m.isEmpty { s.cloudLLMModel = m }
            }
        }
        return s
    }
    private static func loadConfigJSON() -> [String: Any]? {
        let dir = Bundle.main.bundleURL.deletingLastPathComponent()
        let url = FileManager.default.fileExists(atPath: dir.appendingPathComponent("config.json").path)
            ? dir.appendingPathComponent("config.json")
            : Bundle.main.url(forResource: "config", withExtension: "json")
        guard let u = url, let d = try? Data(contentsOf: u) else { return nil }
        return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    }
}
