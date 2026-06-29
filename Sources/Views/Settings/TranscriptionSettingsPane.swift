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

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            SettingsGroup(title: "转写配置") {
                SettingsSectionCard {
                    Picker("转写引擎", selection: $settings.transcriptionEngine) {
                        ForEach(TranscriptionEngine.allCases) { engine in
                            Text(engine.rawValue).tag(engine)
                        }
                    }

                    Picker("语言", selection: $settings.language) {
                        Text("中文").tag("zh-CN")
                        Text("中文（繁体）").tag("zh-TW")
                        Text("中英混合").tag("zh-CN,en-US")
                        Text("English").tag("en-US")
                        Text("日本語").tag("ja-JP")
                    }

                    switch settings.transcriptionEngine {
                    case .whisperLocal:
                        whisperSection
                    case .cloudASR:
                        cloudASRSection
                    case .appleSpeech:
                        SettingsStatusRow(
                            title: "Apple 语音",
                            value: "调用系统语音识别能力，首次验证会请求权限",
                            tint: .secondary
                        )
                    }
                }
            }

            SettingsGroup(title: "转写验证") {
                SettingsSectionCard(tone: .emphasis) {
                    HStack(spacing: 12) {
                        Image(systemName: "waveform.badge.plus")
                            .foregroundStyle(Color.accentColor)
                        Text("使用内置测试音频验证当前转写链路。")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }

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
            validationState = settings.transcriptionValidationState
        }
    }

    private var validationBlocked: Bool {
        switch settings.transcriptionEngine {
        case .whisperLocal:
            return !WhisperModelStore.isAvailable(settings.whisperModel)
        case .cloudASR:
            if settings.cloudASRKey.isEmpty {
                return true
            }

            let baseURL = settings.cloudASRURL.trimmingCharacters(in: .whitespacesAndNewlines)
            return baseURL.isEmpty || baseURL.contains("{WorkspaceId}")
        case .appleSpeech:
            return false
        }
    }

    private var whisperSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()

            SettingsStatusRow(
                title: "whisper-cli",
                value: WhisperRuntime.isCLIAvailable ? "已检测到" : "未检测到",
                tint: WhisperRuntime.isCLIAvailable ? .green : .red
            )

            ForEach(WhisperModel.allCases) { candidate in
                HStack(spacing: 12) {
                    Image(systemName: settings.whisperModel == candidate ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(settings.whisperModel == candidate ? Color.accentColor : .secondary)
                        .onTapGesture {
                            settings.whisperModel = candidate
                        }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(candidate.displayName)
                            .font(.system(size: 14, weight: .semibold))
                        Text(candidate.detail)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if WhisperModelStore.isAvailable(candidate) {
                        SettingsPill(text: "已下载", tint: .green)
                    } else if downloadingModel == candidate {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button("下载 \(candidate.sizeMB)MB") {
                            downloadModel(candidate)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private var cloudASRSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()

            Picker("服务预设", selection: $settings.cloudASRPreset) {
                ForEach(CloudASRPreset.allCases) { preset in
                    Text(preset.rawValue).tag(preset)
                }
            }
            .onChange(of: settings.cloudASRPreset) { _, preset in
                settings.cloudASRURL = preset.defaultURL
                settings.cloudASRModel = preset.defaultModel
            }

            TextField("Base URL", text: $settings.cloudASRURL)
            SecureField("API Key", text: $settings.cloudASRKey)
            TextField("模型名", text: $settings.cloudASRModel)
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
            let provider = TranscriptionService.createProvider(settings: settings)
            do {
                let segments = try await provider.transcribe(audioURL: audioURL, language: settings.language)
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

        Task {
            do {
                try await WhisperModelDownloader.download(candidate)
                await MainActor.run {
                    settings.whisperModel = candidate
                    downloadingModel = nil
                    model.toast = ToastMessage(text: "\(candidate.displayName) 下载完成", level: .success)
                }
            } catch {
                await MainActor.run {
                    downloadingModel = nil
                    model.toast = ToastMessage(text: error.localizedDescription, level: .error)
                }
            }
        }
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
