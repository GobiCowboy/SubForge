import SwiftUI

enum SubtitlePlan: String, CaseIterable, Identifiable {
    case official
    case custom
    case local

    var id: String { rawValue }

    var title: String {
        switch self {
        case .official: "官方智能字幕"
        case .custom: "自定义服务"
        case .local: "本地识别"
        }
    }

    var badge: String? {
        switch self {
        case .official: "推荐"
        case .custom: nil
        case .local: "实验"
        }
    }

    static let localEngines: [TranscriptionEngine] = [
        .funASRLocal,
        .whisperLocal,
        .appleSpeech
    ]

    init(engine: TranscriptionEngine) {
        switch engine {
        case .officialSmart:
            self = .official
        case .cloudASR:
            self = .custom
        case .funASRLocal, .whisperLocal, .appleSpeech:
            self = .local
        }
    }
}

struct SubtitleSettingsPane: View {
    @Binding var settings: AppSettings
    @ObservedObject var service: SmartServiceStore

    @State private var configurationTab: SubtitleConfigurationTab = .transcription
    @State private var isLocalLimitationsExpanded = false

    private var selectedPlan: SubtitlePlan {
        SubtitlePlan(engine: settings.transcriptionEngine)
    }

    var body: some View {
        selectedPlanContent
    }

    @ViewBuilder
    private var selectedPlanContent: some View {
        switch selectedPlan {
        case .official:
            OfficialSmartServicePanel(settings: $settings, service: service)
        case .custom:
            VStack(alignment: .leading, spacing: 28) {
                configurationTabs
                if configurationTab == .transcription {
                    TranscriptionSettingsPane(
                        settings: $settings,
                        allowsOfficialSmart: false,
                        allowedEngines: [.cloudASR],
                        showsEnginePicker: false
                    )
                } else {
                    ProofreadingSettingsPane(settings: $settings)
                }
            }
            .padding(.top, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .local:
            VStack(alignment: .leading, spacing: 18) {
                configurationTabs
                localExperimentalNotice
                if configurationTab == .transcription {
                    TranscriptionSettingsPane(
                        settings: $settings,
                        allowsOfficialSmart: false,
                        allowedEngines: SubtitlePlan.localEngines,
                        enginePickerTitle: "本地模型"
                    )
                } else {
                    ProofreadingSettingsPane(settings: $settings)
                }
            }
            .padding(.top, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var configurationTabs: some View {
        SubtitleConfigurationTabs(selection: $configurationTab, settings: settings)
    }

    private var localExperimentalNotice: some View {
        DisclosureGroup(isExpanded: $isLocalLimitationsExpanded) {
            VStack(alignment: .leading, spacing: 7) {
                Text("转写在本地完成；启用 AI 校对后，将使用你配置的云端服务。")
                VStack(alignment: .leading, spacing: 6) {
                    Text("• 当前时间轴精度较低")
                    Text("• 不建议用于正式字幕制作")
                    Text("• 推荐使用官方智能字幕获得最佳体验")
                }
                .padding(.leading, 16)
            }
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "flask.fill")
                    .foregroundStyle(.orange)
                Text("本地识别（实验）")
                    .font(.system(size: 15, weight: .semibold))
                if !isLocalLimitationsExpanded {
                    Text("时间轴不准确")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(SettingsVisualTokens.standardBorder, lineWidth: SettingsVisualTokens.borderWidth)
        )
    }

}
