import SwiftUI

enum SubtitleConfigurationTab: String, CaseIterable, Identifiable {
    case transcription = "转写"
    case proofreading = "AI 校对"

    var id: String { rawValue }
}

struct SubtitleConfigurationStatus {
    let isConfigured: Bool
    let validationText: String
    let validationIcon: String
    let validationColor: Color

    static func resolve(
        tab: SubtitleConfigurationTab,
        settings: AppSettings
    ) -> SubtitleConfigurationStatus {
        let validation: SettingsValidationState
        let isConfigured: Bool

        switch tab {
        case .transcription:
            validation = settings.transcriptionValidationState
            isConfigured = isTranscriptionConfigured(settings)
        case .proofreading:
            validation = settings.proofreadingValidationState
            var hydratedSettings = settings
            SettingsStore.hydrateSecrets(into: &hydratedSettings, includeASR: false, includeLLM: true)
            isConfigured = hydratedSettings.isProofreadingFullyConfigured
        }

        if !validation.hasValidated {
            return SubtitleConfigurationStatus(
                isConfigured: isConfigured,
                validationText: "未验证",
                validationIcon: "clock",
                validationColor: .secondary
            )
        }

        return SubtitleConfigurationStatus(
            isConfigured: isConfigured,
            validationText: validation.passed ? "验证通过" : "验证失败",
            validationIcon: validation.passed ? "checkmark.shield.fill" : "exclamationmark.triangle.fill",
            validationColor: validation.passed ? .green : .orange
        )
    }

    private static func isTranscriptionConfigured(_ settings: AppSettings) -> Bool {
        switch settings.transcriptionEngine {
        case .officialSmart:
            return true
        case .cloudASR:
            var hydratedSettings = settings
            SettingsStore.hydrateSecrets(into: &hydratedSettings, includeASR: true, includeLLM: false)
            let key = hydratedSettings.cloudASRKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let model = hydratedSettings.effectiveASRModel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: hydratedSettings.effectiveASRURL),
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  url.host?.isEmpty == false else {
                return false
            }
            return !key.isEmpty && !model.isEmpty
        case .funASRLocal:
            return FunASRRuntime.isCLIAvailable && FunASRModelStore.isReady()
        case .whisperLocal:
            return WhisperRuntime.isCLIAvailable && WhisperModelStore.isAvailable(settings.whisperModel)
        case .appleSpeech:
            return true
        }
    }
}

struct SubtitleConfigurationStatusView: View {
    let status: SubtitleConfigurationStatus

    var body: some View {
        HStack(spacing: 12) {
            Label(
                status.isConfigured ? "已配置" : "未配置",
                systemImage: status.isConfigured ? "checkmark.circle.fill" : "circle.dashed"
            )
            .foregroundStyle(status.isConfigured ? Color.accentColor : .secondary)

            Label(status.validationText, systemImage: status.validationIcon)
                .foregroundStyle(status.validationColor)
        }
        .font(.system(size: 11, weight: .medium))
        .lineLimit(1)
    }
}

struct SharedSubtitleSegmentationSettings: View {
    @Binding var settings: AppSettings

    var body: some View {
        SettingsGroup(title: "字幕分段") {
            SettingsListSection {
                SettingsListRow(
                    title: "单条字幕最大字数",
                    description: "适用于官方、自定义和本地转写"
                ) {
                    SettingsTrailingControl(width: SettingsListMetrics.controlWidth) {
                        Stepper(value: maxSubtitleLengthBinding, in: 10...50, step: 2) {
                            Text("\(settings.effectiveMaxSubtitleLength) 字")
                                .monospacedDigit()
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    private var maxSubtitleLengthBinding: Binding<Int> {
        Binding(
            get: { settings.effectiveMaxSubtitleLength },
            set: { settings.maxSubtitleLength = $0 }
        )
    }
}
