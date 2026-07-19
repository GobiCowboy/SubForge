import SwiftUI

private enum SubtitlePlan: String, CaseIterable, Identifiable {
    case official
    case custom
    case local

    var id: String { rawValue }

    var title: String {
        switch self {
        case .official: "官方（推荐）"
        case .custom: "自定义"
        case .local: "本地（实验）"
        }
    }
}

private enum SubtitleConfigurationTab: String, CaseIterable, Identifiable {
    case transcription = "转写"
    case proofreading = "AI 校对"

    var id: String { rawValue }
}

struct SubtitleSettingsPane: View {
    @Binding var settings: AppSettings
    @ObservedObject var service: SmartServiceStore

    @AppStorage("subforge.localTranscriptionEngine")
    private var storedLocalTranscriptionEngine = TranscriptionEngine.funASRLocal.rawValue
    @State private var configurationTab: SubtitleConfigurationTab = .transcription
    @State private var isLocalLimitationsExpanded = false

    private var selectedPlan: SubtitlePlan {
        switch settings.transcriptionEngine {
        case .officialSmart:
            .official
        case .cloudASR:
            .custom
        case .funASRLocal, .whisperLocal, .appleSpeech:
            .local
        }
    }

    private var localTranscriptionEngine: TranscriptionEngine {
        guard let engine = TranscriptionEngine(rawValue: storedLocalTranscriptionEngine),
              Self.localEngines.contains(engine) else {
            return .funASRLocal
        }
        return engine
    }

    private static let localEngines: [TranscriptionEngine] = [
        .funASRLocal,
        .whisperLocal,
        .appleSpeech
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            pageHeader

            HStack(spacing: 0) {
                ForEach(Array(SubtitlePlan.allCases.enumerated()), id: \.element.id) { index, plan in
                    if index > 0 {
                        Divider()
                            .frame(height: 34)
                    }
                    planCard(plan)
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.22), lineWidth: 1)
            )

            selectedPlanContent
        }
        .onAppear(perform: rememberLocalEngineIfNeeded)
        .onChange(of: settings.transcriptionEngine) { _, engine in
            guard Self.localEngines.contains(engine) else { return }
            storedLocalTranscriptionEngine = engine.rawValue
        }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("字幕")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.primary)
            Text("选择生成字幕的方式")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
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
            .frame(maxWidth: .infinity, alignment: .leading)
        case .local:
            VStack(alignment: .leading, spacing: 18) {
                localExperimentalNotice

                configurationTabs
                if configurationTab == .transcription {
                    TranscriptionSettingsPane(
                        settings: $settings,
                        allowsOfficialSmart: false,
                        allowedEngines: Self.localEngines,
                        enginePickerTitle: "本地模型"
                    )
                } else {
                    ProofreadingSettingsPane(settings: $settings)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func planCard(_ plan: SubtitlePlan) -> some View {
        let isSelected = selectedPlan == plan

        return Button {
            select(plan)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                Text(plan.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(
                isSelected ? Color.accentColor.opacity(0.06) : Color.clear
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: 58)
        .accessibilityLabel(plan.title)
        .accessibilityValue(isSelected ? "已选择" : "未选择")
    }

    private var configurationTabs: some View {
        Picker("", selection: $configurationTab) {
            ForEach(SubtitleConfigurationTab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.large)
        .frame(minWidth: 584, maxWidth: .infinity)
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
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.16), lineWidth: 1)
        )
    }

    private func select(_ plan: SubtitlePlan) {
        isLocalLimitationsExpanded = false
        switch plan {
        case .official:
            rememberLocalEngineIfNeeded()
            settings.transcriptionEngine = .officialSmart
            configurationTab = .transcription
        case .custom:
            rememberLocalEngineIfNeeded()
            settings.transcriptionEngine = .cloudASR
            configurationTab = .transcription
        case .local:
            settings.transcriptionEngine = localTranscriptionEngine
            configurationTab = .transcription
        }
    }

    private func rememberLocalEngineIfNeeded() {
        guard Self.localEngines.contains(settings.transcriptionEngine) else { return }
        storedLocalTranscriptionEngine = settings.transcriptionEngine.rawValue
    }
}
