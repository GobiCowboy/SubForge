import SwiftUI

struct TranscriptionSettingsPane: View {
    @EnvironmentObject private var model: AppModel
    @Binding var settings: AppSettings
    var allowsOfficialSmart: Bool = true
    var allowedEngines: [TranscriptionEngine]? = nil
    var showsEnginePicker: Bool = true
    var enginePickerTitle: String = "转写引擎"

    @State private var isTesting = false
    @State private var validationState = SettingsValidationState()
    @State private var isValidationExpanded = false
    @State private var downloadingModel: WhisperModel?
    @State private var downloadProgress: Double?
    @State private var isDownloadingFunASR = false
    @State private var funASRDownloadProgress: Double?
    @State private var validationTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            SettingsGroup(title: "转写配置") {
                SettingsListSection {
                    if showsEnginePicker {
                        enginePickerControl
                    }
                    languagePickerControl
                    subtitleSegmentationControls

                    switch settings.transcriptionEngine {
                    case .cloudASR:
                        cloudASRControls
                    case .officialSmart:
                        SettingsListRow(title: "智能字幕") {
                            Text("在「智能服务」中购买与查看额度")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    case .appleSpeech:
                        SettingsListRow(title: "Apple 语音") {
                            Text("已启用")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    case .whisperLocal, .funASRLocal:
                        EmptyView()
                    }
                }
            }

            switch settings.transcriptionEngine {
            case .whisperLocal:
                whisperSection
            case .funASRLocal:
                funASRSection
            case .cloudASR, .officialSmart, .appleSpeech:
                EmptyView()
            }

            SettingsDisclosureSection(title: "转写验证", isExpanded: $isValidationExpanded) {
                HStack(spacing: 12) {
                    Button(action: runTranscriptionTest) {
                        HStack(spacing: 8) {
                            if isTesting {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Label(isTesting ? "验证中..." : "验证当前转写配置", systemImage: "checkmark.shield")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(isTesting || validationBlocked)

                    if validationState.hasValidated {
                        Text(validationState.passed ? "验证通过" : "验证未通过")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(validationState.passed ? .green : .orange)
                    }

                    Spacer(minLength: 0)
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

    private var enginePickerControl: some View {
        SettingsListRow(title: enginePickerTitle) {
            Picker(enginePickerTitle, selection: $settings.transcriptionEngine) {
                ForEach(selectableEngines) { engine in
                    Text(engine.rawValue).tag(engine)
                }
            }
            .labelsHidden()
            .frame(width: SettingsListMetrics.pickerWidth)
        }
    }

    private var languagePickerControl: some View {
        SettingsListRow(title: "语言") {
            Picker("语言", selection: $settings.language) {
                Text("中文").tag("zh-CN")
                Text("中文（繁体）").tag("zh-TW")
                Text("中英混合").tag("zh-CN,en-US")
                Text("English").tag("en-US")
                Text("日本語").tag("ja-JP")
                Text("한국어").tag("ko-KR")
            }
            .labelsHidden()
            .frame(width: SettingsListMetrics.pickerWidth)
        }
    }

    private var selectableEngines: [TranscriptionEngine] {
        let engines = allowedEngines ?? TranscriptionEngine.allCases
        return engines.filter { allowsOfficialSmart || $0 != .officialSmart }
    }

    private var validationBlocked: Bool {
        switch settings.transcriptionEngine {
        case .whisperLocal:
            return !WhisperRuntime.isCLIAvailable || !WhisperModelStore.isAvailable(settings.whisperModel)
        case .funASRLocal:
            return !FunASRRuntime.isCLIAvailable || !FunASRModelStore.isReady()
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
        case .officialSmart:
            // 官方服务按实际秒数扣费，不用设置页测试音频隐式消耗。
            return true
        }
    }

    private var subtitleSegmentationControls: some View {
        SettingsListRow(title: "单条字幕最大字数") {
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
                Text("本地 Whisper")
                    .font(.system(size: 13, weight: .semibold))

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

    private var funASRSection: some View {
        SettingsInsetPanel {
            HStack {
                Text("本地 FunASR / SenseVoice")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                SettingsPill(
                    text: FunASRRuntime.isCLIAvailable ? "运行时已检测" : "运行时缺失",
                    tint: FunASRRuntime.isCLIAvailable ? .green : .red
                )
            }

            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text(FunASRModel.sensevoiceSmallQ8.displayName)
                        .font(.system(size: 13, weight: .semibold))
                }

                Spacer()

                if FunASRModelStore.isReady() {
                    SettingsPill(
                        text: FunASRModelStore.isBundled() ? "已内置" : "已就绪",
                        tint: .green
                    )
                } else if isDownloadingFunASR {
                    VStack(alignment: .trailing, spacing: 4) {
                        ProgressView(value: funASRDownloadProgress ?? 0)
                            .frame(width: 96)
                        Text(funASRDownloadProgressText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button("下载 \(FunASRModel.sensevoiceSmallQ8.sizeMB + FunASRModelStore.vadSizeMB)MB") {
                        downloadFunASRModel()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.08))
            )

            if !FunASRRuntime.isCLIAvailable {
                Text("缺少 llama-funasr-sensevoice。开发环境请运行 script/download_funasr_runtime.sh，正式包需重新构建以嵌入运行时。")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
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

    @ViewBuilder
    private var cloudASRControls: some View {
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

        validationTask?.cancel()
        Task { await FunASRCLIRunner.shared.cancelActive() }

        isTesting = true
        validationState.resultText = "正在调用当前转写链路..."

        validationTask = Task {
            var testSettings = settings
            SettingsStore.hydrateSecrets(into: &testSettings, includeASR: true, includeLLM: false)
            let provider = TranscriptionService.createProvider(settings: testSettings)
            do {
                let segments = try await provider.transcribe(audioURL: audioURL, language: testSettings.language)
                try Task.checkCancellation()
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
            } catch is CancellationError {
                await MainActor.run {
                    isTesting = false
                    validationState.resultText = "已取消上一次验证"
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

    private func downloadFunASRModel() {
        isDownloadingFunASR = true
        funASRDownloadProgress = 0

        Task {
            do {
                try await FunASRModelDownloader.download(.sensevoiceSmallQ8) { progress in
                    Task { @MainActor in
                        if isDownloadingFunASR {
                            funASRDownloadProgress = progress
                        }
                    }
                }
                await MainActor.run {
                    isDownloadingFunASR = false
                    funASRDownloadProgress = nil
                    model.toast = ToastMessage(text: "SenseVoice + VAD 下载完成", level: .success)
                }
            } catch {
                await MainActor.run {
                    isDownloadingFunASR = false
                    funASRDownloadProgress = nil
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

    private var funASRDownloadProgressText: String {
        guard let funASRDownloadProgress else {
            return "下载中..."
        }
        return "下载中 \(Int(funASRDownloadProgress * 100))%"
    }
}
