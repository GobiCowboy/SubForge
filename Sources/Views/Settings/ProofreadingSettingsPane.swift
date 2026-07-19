import SwiftUI

struct ProofreadingSettingsPane: View {
    @EnvironmentObject private var model: AppModel
    @Binding var settings: AppSettings

    @State private var isTesting = false
    @State private var validationState = SettingsValidationState()
    @State private var isValidationExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            if let configurationStatusText {
                SettingsTipBox(text: configurationStatusText)
            }

            SettingsGroup(title: "AI 校对配置") {
                SettingsListSection {
                    SettingsListRow(title: "启用模型纠正") {
                        Toggle("", isOn: $settings.proofreadingEnabled)
                            .labelsHidden()
                    }

                    if settings.proofreadingEnabled {
                        SettingsListRow(title: "服务预设") {
                            SettingsTrailingControl {
                                Picker("服务预设", selection: $settings.cloudLLMPreset) {
                                    ForEach(CloudLLMPreset.allCases) { preset in
                                        Text(preset.rawValue).tag(preset)
                                    }
                                }
                                .labelsHidden()
                                .onChange(of: settings.cloudLLMPreset) { _, preset in
                                    settings.cloudLLMURL = preset.defaultURL
                                    settings.cloudLLMModel = preset.defaultModel
                                    settings.proofreadingEngine = .cloudLLM
                                }
                            }
                        }

                        SettingsListRow(title: "Base URL") {
                            TextField("Base URL", text: $settings.cloudLLMURL)
                                .textFieldStyle(.roundedBorder)
                                .help(settings.cloudLLMURL)
                        }

                        SettingsListRow(title: "API Key") {
                            SecureField("API Key", text: $settings.cloudLLMKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        SettingsListRow(title: "模型") {
                            TextField("模型名", text: $settings.cloudLLMModel)
                                .textFieldStyle(.roundedBorder)
                                .help(settings.cloudLLMModel)
                        }

                        SettingsListRow(title: "提示词", alignment: .top) {
                            TextEditor(text: $settings.proofreadingPrompt)
                                .font(.system(size: 14))
                                .frame(height: 88)
                                .padding(10)
                                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.18))
                                )
                        }
                    }
                }
            }

            SettingsValidationSection(
                title: "AI 校对验证",
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
            validationState = settings.proofreadingValidationState
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
        .onChange(of: settings.cloudLLMKey) { oldValue, newValue in
            if !oldValue.isEmpty, newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                SettingsStore.deleteLLMKey()
            }
            // Key 被清空且仍开着校对：立刻提醒
            if settings.proofreadingEnabled,
               newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let warning = settings.proofreadingConfigWarning {
                model.notifyUser(warning, level: .error, duration: 3.5)
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

    private func runProofreadingTest() {
        isTesting = true
        validationState.resultText = "正在调用当前模型纠正链路..."
        settings.proofreadingEngine = .cloudLLM

        Task {
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
            settings.cloudLLMKey = hydratedSettings.cloudLLMKey
        }
    }

    private func persistValidationState(_ state: SettingsValidationState) {
        validationState = state
        settings.proofreadingValidationState = state
    }

}
