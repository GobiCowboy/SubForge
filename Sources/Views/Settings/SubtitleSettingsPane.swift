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
            VStack(alignment: .leading, spacing: 28) {
                configurationTabs
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

}
