import SwiftUI

extension TranscriptionSettingsPane {
    var enginePickerControl: some View {
        SettingsListRow(title: enginePickerTitle) {
            SettingsTrailingControl(width: SettingsListMetrics.controlWidth) {
                Picker(enginePickerTitle, selection: localEngineBinding) {
                    ForEach(selectableEngines) { engine in
                        Text(engine.rawValue).tag(engine)
                    }
                }
                .labelsHidden()
            }
        }
    }

    var languagePickerControl: some View {
        SettingsListRow(title: "语言") {
            SettingsTrailingControl(width: SettingsListMetrics.controlWidth) {
                Picker("语言", selection: languageBinding) {
                    Text("中文").tag("zh-CN")
                    Text("中文（繁体）").tag("zh-TW")
                    Text("中英混合").tag("zh-CN,en-US")
                    Text("English").tag("en-US")
                    Text("日本語").tag("ja-JP")
                    Text("한국어").tag("ko-KR")
                }
                .labelsHidden()
            }
        }
    }

    var selectableEngines: [TranscriptionEngine] {
        let engines = allowedEngines ?? TranscriptionEngine.allCases
        return engines.filter { allowsOfficialSmart || $0 != .officialSmart }
    }

    var transcriptionValidationTitle: String {
        if validationState.hasValidated, !validationState.passed {
            return "转写验证失败"
        }
        return "转写验证"
    }

    var validationBlocked: Bool {
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

    var whisperSection: some View {
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

    var funASRSection: some View {
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

    func whisperModelRow(_ candidate: WhisperModel) -> some View {
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
            cancelValidation()
            settings.setLocalWhisperModel(candidate)
        }
    }

    @ViewBuilder
    var cloudASRControls: some View {
        SettingsListRow(title: "服务预设") {
            SettingsTrailingControl {
                Picker("服务预设", selection: customPresetBinding) {
                    ForEach(CloudASRPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .labelsHidden()
            }
        }

        SettingsListRow(title: "Base URL") {
            TextField("Base URL", text: customURLBinding)
                .textFieldStyle(.roundedBorder)
                .help(settings.cloudASRURL)
        }

        SettingsListRow(title: "API Key") {
            SecureField("API Key", text: customKeyBinding)
                .textFieldStyle(.roundedBorder)
        }

        SettingsListRow(title: "模型") {
            TextField("模型名", text: customModelBinding)
                .textFieldStyle(.roundedBorder)
                .help(settings.cloudASRModel)
        }
    }

    var localEngineBinding: Binding<TranscriptionEngine> {
        Binding(
            get: { settings.transcriptionEngine },
            set: {
                cancelValidation()
                settings.setLocalTranscriptionEngine($0)
            }
        )
    }

    var languageBinding: Binding<String> {
        Binding(
            get: { settings.language },
            set: {
                cancelValidation()
                settings.setTranscriptionLanguage($0)
            }
        )
    }

    var customPresetBinding: Binding<CloudASRPreset> {
        Binding(
            get: { settings.cloudASRPreset },
            set: {
                cancelValidation()
                settings.setCustomASRPreset($0)
            }
        )
    }

    var customURLBinding: Binding<String> {
        Binding(
            get: { settings.cloudASRURL },
            set: {
                cancelValidation()
                settings.setCustomASRURL($0)
            }
        )
    }

    var customKeyBinding: Binding<String> {
        Binding(
            get: { settings.cloudASRKey },
            set: {
                cancelValidation()
                if !settings.cloudASRKey.isEmpty,
                   $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    SettingsStore.deleteASRKey()
                }
                settings.setCustomASRKey($0)
            }
        )
    }

    var customModelBinding: Binding<String> {
        Binding(
            get: { settings.cloudASRModel },
            set: {
                cancelValidation()
                settings.setCustomASRModel($0)
            }
        )
    }
}
