import AppKit
import SwiftUI

struct ProofreadingSettingsPane: View {
    @EnvironmentObject private var model: AppModel
    @Binding var settings: AppSettings

    @State private var isTesting = false
    @State private var validationState = SettingsValidationState()

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            SettingsGroup(title: "校对配置") {
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

            SettingsGroup(title: "校对验证") {
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

                    SettingsActionRow {
                        Button(action: copySampleText) {
                            Label("复制原始文本", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    } secondary: {
                        Button(action: runProofreadingTest) {
                            HStack(spacing: 8) {
                                if isTesting {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text(isTesting ? "验证中..." : "验证当前模型纠正配置")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(isTesting || !settings.proofreadingEnabled || settings.cloudLLMKey.isEmpty)
                    }
                }
            }
        }
        .onAppear {
            if settings.proofreadingEngine == .appleLocal {
                settings.proofreadingEngine = .cloudLLM
            }
            validationState = settings.proofreadingValidationState
        }
    }

    private func runProofreadingTest() {
        isTesting = true
        validationState.resultText = "正在调用当前模型纠正链路..."
        settings.proofreadingEngine = .cloudLLM

        Task {
            let provider = CloudLLMProvider(
                apiURL: settings.effectiveLLMURL,
                apiKey: settings.cloudLLMKey,
                model: settings.effectiveLLMModel
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

    private func persistValidationState(_ state: SettingsValidationState) {
        validationState = state
        settings.proofreadingValidationState = state
    }

    private func copySampleText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(SettingsTestAsset.proofreadingSampleInput, forType: .string)
        model.toast = ToastMessage(text: "已复制原始文本", level: .success)
    }
}
