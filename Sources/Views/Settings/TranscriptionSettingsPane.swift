import SwiftUI

enum TranscriptionValidationScope {
    case custom
    case local
}

struct TranscriptionSettingsPane: View {
    @EnvironmentObject var model: AppModel
    @Binding var settings: AppSettings
    let validationScope: TranscriptionValidationScope
    var allowsOfficialSmart: Bool = true
    var allowedEngines: [TranscriptionEngine]? = nil
    var showsEnginePicker: Bool = true
    var enginePickerTitle: String = "转写引擎"

    @State var isTesting = false
    @State var isValidationExpanded = false
    @State var downloadingModel: WhisperModel?
    @State var downloadProgress: Double?
    @State var isDownloadingFunASR = false
    @State var funASRDownloadProgress: Double?
    @State var validationTask: Task<Void, Never>?

    var validationState: SettingsValidationState {
        switch validationScope {
        case .custom:
            settings.customTranscriptionValidationState
        case .local:
            settings.localTranscriptionValidationState
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsListSection {
                languagePickerControl
                if showsEnginePicker {
                    enginePickerControl
                }

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

            switch settings.transcriptionEngine {
            case .whisperLocal:
                whisperSection
            case .funASRLocal:
                funASRSection
            case .cloudASR, .officialSmart, .appleSpeech:
                EmptyView()
            }

            SettingsListSection {
                SettingsListRow(title: "单条字幕最大字数", controlWidth: 360) {
                    SubtitleLengthSlider(
                        settings: $settings,
                        profile: settings.subtitleLengthProfile
                    )
                }
            }

            SettingsValidationSection(
                title: transcriptionValidationTitle,
                isExpanded: $isValidationExpanded,
                state: validationState,
                action: {
                    Button(action: runTranscriptionTest) {
                        HStack(spacing: 8) {
                            if isTesting {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Label(isTesting ? "验证中..." : "验证", systemImage: "checkmark.shield")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(isTesting || validationBlocked)
                }
            ) {
                    SettingsValidationResultBox(
                        title: "测试音频原文",
                        hasValidated: validationState.hasValidated,
                        isSuccess: validationState.passed,
                        originalText: SettingsTestAsset.expectedASRText,
                        resultText: validationState.resultText
                    )
            }
        }
        .onAppear {
            if validationScope == .custom {
                hydrateCloudASRKeyIfNeeded()
            }
        }
        .onChange(of: settings.transcriptionEngine) { _, _ in
            validationTask?.cancel()
            isTesting = false
        }
    }
}
