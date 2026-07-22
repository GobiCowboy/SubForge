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

struct SubtitleConfigurationTabs: View {
    @Binding var selection: SubtitleConfigurationTab
    let settings: AppSettings

    var body: some View {
        HStack(spacing: 28) {
            ForEach(SubtitleConfigurationTab.allCases) { tab in
                tabButton(tab)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func tabButton(_ tab: SubtitleConfigurationTab) -> some View {
        let selected = selection == tab
        let isConfigured = SubtitleConfigurationStatus.resolve(tab: tab, settings: settings).isConfigured

        return Button {
            selection = tab
        } label: {
            HStack(spacing: 7) {
                Text(tab.rawValue)
                    .font(.system(size: 16, weight: .semibold))

                Image(systemName: isConfigured ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isConfigured ? .green : .secondary)
            }
            .foregroundStyle(selected ? Color.accentColor : .primary)
            .frame(height: 42)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(selected ? Color.accentColor : Color.clear)
                    .frame(height: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

struct SubtitleLengthSlider: View {
    @Binding var settings: AppSettings
    let profile: SubtitleLengthProfile

    var body: some View {
        HStack(spacing: 12) {
            Slider(value: maxSubtitleLengthBinding, in: 10...50, step: 2)
                .frame(maxWidth: .infinity)

            Text("\(settings.effectiveMaxSubtitleLength(for: profile)) 字")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
    }

    private var maxSubtitleLengthBinding: Binding<Double> {
        Binding(
            get: { Double(settings.effectiveMaxSubtitleLength(for: profile)) },
            set: { settings.setMaxSubtitleLength(Int($0.rounded()), for: profile) }
        )
    }
}
