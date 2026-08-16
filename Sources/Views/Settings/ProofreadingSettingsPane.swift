import SwiftUI

struct ProofreadingSettingsPane: View {
    @EnvironmentObject private var model: AppModel
    @Binding var settings: AppSettings

    @State private var isTesting = false
    @State private var isValidationExpanded = false
    @State var validationTask: Task<Void, Never>?

    private var validationState: SettingsValidationState {
        settings.proofreadingValidationState
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            if let configurationStatusText {
                SettingsTipBox(text: configurationStatusText)
            }

            SettingsListSection {
                    SettingsListRow(title: "启用模型纠正") {
                        Toggle("", isOn: proofreadingEnabledBinding)
                            .labelsHidden()
                    }

                    if settings.proofreadingEnabled {
                        SettingsListRow(title: "服务预设") {
                            SettingsTrailingControl {
                                Picker("服务预设", selection: proofreadingPresetBinding) {
                                    ForEach(CloudLLMPreset.allCases) { preset in
                                        Text(preset.rawValue).tag(preset)
                                    }
                                }
                                .labelsHidden()
                            }
                        }

                        SettingsListRow(title: "Base URL") {
                            TextField("Base URL", text: proofreadingURLBinding)
                                .textFieldStyle(.roundedBorder)
                                .help(settings.cloudLLMURL)
                        }

                        SettingsListRow(title: "API Key") {
                            SecureField("API Key", text: proofreadingKeyBinding)
                                .textFieldStyle(.roundedBorder)
                        }

                        SettingsListRow(title: "模型") {
                            TextField("模型名", text: proofreadingModelBinding)
                                .textFieldStyle(.roundedBorder)
                                .help(settings.cloudLLMModel)
                        }

                    }
            }

            SettingsValidationSection(
                title: proofreadingValidationTitle,
                isExpanded: $isValidationExpanded,
                state: validationState,
                action: {
                    Button(action: runProofreadingTest) {
                        HStack(spacing: 8) {
                            if isTesting {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(isTesting ? "验证中..." : "验证")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(isTesting || !settings.proofreadingEnabled || settings.cloudLLMKey.isEmpty)
                }
            ) {
                    SettingsSectionCard(tone: .emphasis) {
                        SettingsStatusRow(
                            title: "当前模型",
                            value: settings.effectiveLLMModel,
                            tint: .secondary
                        )

                        SettingsValidationResultBox(
                            title: "原始文本",
                            hasValidated: validationState.hasValidated,
                            isSuccess: validationState.passed,
                            originalText: SettingsTestAsset.proofreadingSampleInput,
                            resultText: validationState.resultText
                        )
                    }
                }
        }
        .onAppear {
            if settings.proofreadingEngine == .appleLocal {
                settings.proofreadingEngine = .cloudLLM
            }
            hydrateCloudLLMKeyIfNeeded()
        }
        .onChange(of: settings.proofreadingEnabled) { _, enabled in
            if enabled {
                hydrateCloudLLMKeyIfNeeded()
                // 打开开关立刻提醒：别等到转写结束才发现没配 Key
                if let warning = settings.proofreadingConfigWarning {
                    model.notifyUser(warning + "。转写时将跳过校对。", level: .error, duration: 4.5)
                }
            }
        }
    }

    private var configurationStatusText: String? {
        if !settings.proofreadingEnabled {
            return "未配置 AI 校对。当前仅进行转写。"
        }
        if let warning = settings.proofreadingConfigWarning {
            return "\(warning)。当前仅进行转写。"
        }
        return nil
    }

    private var proofreadingValidationTitle: String {
        if validationState.hasValidated, !validationState.passed {
            return "AI 校对验证失败"
        }
        return "AI 校对验证"
    }

    private func runProofreadingTest() {
        validationTask?.cancel()
        isTesting = true
        settings.proofreadingEngine = .cloudLLM

        validationTask = Task {
            var testSettings = settings
            SettingsStore.hydrateSecrets(into: &testSettings, includeASR: false, includeLLM: true)
            let provider = CloudLLMProvider(
                apiURL: testSettings.effectiveLLMURL,
                apiKey: testSettings.cloudLLMKey,
                model: testSettings.effectiveLLMModel
            )

            do {
                let corrected = try await provider.proofread(
                    segments: [SubtitleSegment(start: 0, end: 1, text: SettingsTestAsset.proofreadingSampleInput)],
                    batchSize: 1,
                    prompt: settings.proofreadingPrompt,
                    strictCorrections: settings.proofreadingStrictCorrections
                )
                let result = corrected.first?.text ?? ""
                try Task.checkCancellation()
                await MainActor.run {
                    let state = SettingsValidationState(
                        hasValidated: true,
                        passed: !result.isEmpty,
                        resultText: result.isEmpty ? "纠正完成，但没有得到输出。" : result
                    )
                    persistValidationState(state)
                    isTesting = false
                }
            } catch {
                guard !Task.isCancelled else {
                    await MainActor.run {
                        isTesting = false
                    }
                    return
                }
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

    private func hydrateCloudLLMKeyIfNeeded() {
        guard settings.proofreadingEnabled else { return }
        var hydratedSettings = settings
        SettingsStore.hydrateSecrets(into: &hydratedSettings, includeASR: false, includeLLM: true)
        if hydratedSettings.cloudLLMKey != settings.cloudLLMKey {
            settings.hydrateProofreadingKey(hydratedSettings.cloudLLMKey)
        }
    }

    private func persistValidationState(_ state: SettingsValidationState) {
        settings.proofreadingValidationState = state
    }

    func cancelValidation() {
        validationTask?.cancel()
        validationTask = nil
        isTesting = false
    }

}
