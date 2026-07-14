import AVFoundation
import SwiftUI

struct TranscriptionSettingsPane: View {
    @EnvironmentObject private var model: AppModel
    @Binding var settings: AppSettings

    @State private var isTesting = false
    @State private var validationState = SettingsValidationState()
    @State private var isPlayingTestAudio = false
    @State private var audioPlayer: AVAudioPlayer?
    @State private var audioDelegate: SettingsAudioPlayDelegate?
    @State private var downloadingModel: WhisperModel?
    @State private var downloadProgress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            SettingsGroup(title: "转写配置") {
                SettingsListSection {
                    transcriptionHeaderControls
                    subtitleSegmentationControls

                    switch settings.transcriptionEngine {
                    case .whisperLocal:
                        whisperSection
                    case .cloudASR:
                        cloudASRSection
                    case .appleSpeech:
                        SettingsListRow(
                            title: "Apple 语音",
                            description: "调用系统语音识别能力，首次验证会请求权限。"
                        ) {
                            Text("已启用")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            SettingsGroup(title: "转写验证") {
                SettingsSectionCard(tone: .emphasis) {
                    SettingsStatusRow(
                        title: "当前引擎",
                        value: settings.transcriptionEngine.rawValue,
                        tint: .secondary
                    )

                    SettingsValidationResultBox(
                        title: "测试音频原文",
                        hasValidated: validationState.hasValidated,
                        isSuccess: validationState.passed,
                        originalText: SettingsTestAsset.expectedASRText,
                        resultText: validationState.resultText
                    )

                    SettingsActionRow {
                        Button(action: toggleTestAudio) {
                            Label(isPlayingTestAudio ? "停止试听" : "试听测试音频", systemImage: isPlayingTestAudio ? "stop.fill" : "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    } secondary: {
                        Button(action: runTranscriptionTest) {
                            HStack(spacing: 8) {
                                if isTesting {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text(isTesting ? "验证中..." : "验证当前转写配置")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(isTesting || validationBlocked)
                    }
                }
            }
        }
        .onAppear {
            hydrateCloudASRKeyIfNeeded()
            validationState = settings.transcriptionValidationState
        }
        .onChange(of: settings.transcriptionEngine) { _, engine in
            if engine == .cloudASR {
                hydrateCloudASRKeyIfNeeded()
            }
        }
        .onChange(of: settings.cloudASRKey) { oldValue, newValue in
            if !oldValue.isEmpty, newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                SettingsStore.deleteASRKey()
            }
        }
    }

    private var transcriptionHeaderControls: some View {
        HStack(spacing: 12) {
            SettingsCompactPicker(title: "转写引擎", systemImage: "waveform") {
                Picker("转写引擎", selection: $settings.transcriptionEngine) {
                    ForEach(TranscriptionEngine.allCases) { engine in
                        Text(engine.rawValue).tag(engine)
                    }
                }
                .labelsHidden()
                .frame(width: 168)
            }

            SettingsCompactPicker(title: "语言", systemImage: "globe") {
                Picker("语言", selection: $settings.language) {
                    Text("中文").tag("zh-CN")
                    Text("中文（繁体）").tag("zh-TW")
                    Text("中英混合").tag("zh-CN,en-US")
                    Text("English").tag("en-US")
                    Text("日本語").tag("ja-JP")
                }
                .labelsHidden()
                .frame(width: 168)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var validationBlocked: Bool {
        switch settings.transcriptionEngine {
        case .whisperLocal:
            return !WhisperRuntime.isCLIAvailable || !WhisperModelStore.isAvailable(settings.whisperModel)
        case .cloudASR:
            var hydratedSettings = settings
            SettingsStore.hydrateSecrets(into: &hydratedSettings, includeASR: true, includeLLM: false)
            if hydratedSettings.cloudASRKey.isEmpty {
                return true
            }

            let baseURL = settings.cloudASRURL.trimmingCharacters(in: .whitespacesAndNewlines)
            return baseURL.isEmpty || baseURL.contains("{WorkspaceId}")
        case .appleSpeech:
            return false
        }
    }

    private var subtitleSegmentationControls: some View {
        SettingsListRow(
            title: "单条字幕最大字数",
            description: "适用于 Apple 语音、本地 Whisper 和云端 ASR。"
        ) {
            Stepper(value: maxSubtitleLengthBinding, in: 10...50, step: 2) {
                Text("\(settings.effectiveMaxSubtitleLength) 字")
                    .monospacedDigit()
                    .frame(width: 48, alignment: .trailing)
            }
            .frame(width: 156)
        }
    }

    private var maxSubtitleLengthBinding: Binding<Int> {
        Binding(
            get: { settings.effectiveMaxSubtitleLength },
            set: { settings.maxSubtitleLength = $0 }
        )
    }

    private var whisperSection: some View {
        SettingsInsetPanel {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("本地 Whisper")
                        .font(.system(size: 13, weight: .semibold))
                    Text("离线转写，模型越大质量越好。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                SettingsPill(
                    text: WhisperRuntime.isCLIAvailable ? "已检测到" : "未检测到",
                    tint: WhisperRuntime.isCLIAvailable ? .green : .red
                )
            }

            VStack(spacing: 8) {
                ForEach(WhisperModel.allCases) { candidate in
                    whisperModelRow(candidate)
                }
            }
        }
    }

    private func whisperModelRow(_ candidate: WhisperModel) -> some View {
        let isSelected = settings.whisperModel == candidate

        return HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.displayName)
                    .font(.system(size: 13, weight: .semibold))
                Text(candidate.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if WhisperModelStore.isAvailable(candidate) {
                SettingsPill(
                    text: WhisperModelStore.isBundled(candidate) ? "已内置" : "已下载",
                    tint: .green
                )
            } else if downloadingModel == candidate {
                VStack(alignment: .trailing, spacing: 4) {
                    ProgressView(value: downloadProgress ?? 0)
                        .frame(width: 96)
                    Text(downloadProgressText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("下载 \(candidate.sizeMB)MB") {
                    downloadModel(candidate)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture {
            settings.whisperModel = candidate
        }
    }

    private var cloudASRSection: some View {
        SettingsInsetPanel {
            VStack(alignment: .leading, spacing: 4) {
                Text("云端 ASR")
                    .font(.system(size: 13, weight: .semibold))
                Text("阿里默认：异步 transcription + qwen3-asr-flash-filetrans。本地音频会先走百炼临时上传再转写，无需自建 OSS。Base URL 须以 /api/v1/services/audio/asr/transcription 结尾，不要填 compatible-mode。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            SettingsListRow(title: "服务预设") {
                SettingsTrailingControl {
                    Picker("服务预设", selection: $settings.cloudASRPreset) {
                        ForEach(CloudASRPreset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: settings.cloudASRPreset) { _, preset in
                        settings.cloudASRURL = preset.defaultURL
                        settings.cloudASRModel = preset.defaultModel
                    }
                }
            }

            SettingsListRow(title: "Base URL") {
                TextField("Base URL", text: $settings.cloudASRURL)
                    .textFieldStyle(.roundedBorder)
                    .help(settings.cloudASRURL)
            }

            SettingsListRow(title: "API Key") {
                SecureField("API Key", text: $settings.cloudASRKey)
                    .textFieldStyle(.roundedBorder)
            }

            SettingsListRow(title: "模型") {
                TextField("模型名", text: $settings.cloudASRModel)
                    .textFieldStyle(.roundedBorder)
                    .help(settings.cloudASRModel)
            }
        }
    }

    private func runTranscriptionTest() {
        guard let audioURL = SettingsTestAsset.audioURL() else {
            persistValidationState(
                SettingsValidationState(
                    hasValidated: true,
                    passed: false,
                    resultText: "没有找到测试音频，请确认应用已打包测试资源。"
                )
            )
            return
        }

        isTesting = true
        validationState.resultText = "正在调用当前转写链路..."

        Task {
            var testSettings = settings
            SettingsStore.hydrateSecrets(into: &testSettings, includeASR: true, includeLLM: false)
            let provider = TranscriptionService.createProvider(settings: testSettings)
            do {
                let segments = try await provider.transcribe(audioURL: audioURL, language: testSettings.language)
                let result = segments.map(\.text).joined(separator: "\n")
                await MainActor.run {
                    let state = SettingsValidationState(
                        hasValidated: true,
                        passed: !result.isEmpty,
                        resultText: result.isEmpty ? "识别完成，但没有得到可用文本。" : result
                    )
                    persistValidationState(state)
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    let state = SettingsValidationState(
                        hasValidated: true,
                        passed: false,
                        resultText: error.localizedDescription
                    )
                    persistValidationState(state)
                    isTesting = false
                }
            }
        }
    }

    private func hydrateCloudASRKeyIfNeeded() {
        guard settings.transcriptionEngine == .cloudASR else { return }
        var hydratedSettings = settings
        SettingsStore.hydrateSecrets(into: &hydratedSettings, includeASR: true, includeLLM: false)
        if hydratedSettings.cloudASRKey != settings.cloudASRKey {
            settings.cloudASRKey = hydratedSettings.cloudASRKey
        }
    }

    private func persistValidationState(_ state: SettingsValidationState) {
        validationState = state
        settings.transcriptionValidationState = state
    }

    private func toggleTestAudio() {
        if isPlayingTestAudio {
            audioPlayer?.stop()
            isPlayingTestAudio = false
            return
        }

        guard let audioURL = SettingsTestAsset.audioURL() else {
            model.toast = ToastMessage(text: "测试音频不存在", level: .error)
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: audioURL)
            let delegate = SettingsAudioPlayDelegate {
                isPlayingTestAudio = false
            }
            audioPlayer = player
            audioDelegate = delegate
            player.delegate = delegate
            player.play()
            isPlayingTestAudio = true
        } catch {
            model.toast = ToastMessage(text: "播放测试音频失败：\(error.localizedDescription)", level: .error)
        }
    }

    private func downloadModel(_ candidate: WhisperModel) {
        downloadingModel = candidate
        downloadProgress = 0

        Task {
            do {
                try await WhisperModelDownloader.download(candidate) { progress in
                    Task { @MainActor in
                        if downloadingModel == candidate {
                            downloadProgress = progress
                        }
                    }
                }
                await MainActor.run {
                    settings.whisperModel = candidate
                    downloadingModel = nil
                    downloadProgress = nil
                    model.toast = ToastMessage(text: "\(candidate.displayName) 下载完成", level: .success)
                }
            } catch {
                await MainActor.run {
                    downloadingModel = nil
                    downloadProgress = nil
                    model.toast = ToastMessage(text: error.localizedDescription, level: .error)
                }
            }
        }
    }

    private var downloadProgressText: String {
        guard let downloadProgress else {
            return "下载中..."
        }
        return "下载中 \(Int(downloadProgress * 100))%"
    }
}

private final class SettingsAudioPlayDelegate: NSObject, AVAudioPlayerDelegate {
    let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}
