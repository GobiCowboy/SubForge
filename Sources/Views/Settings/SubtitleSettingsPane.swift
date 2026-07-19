import SwiftUI

private enum CustomSubtitleTab: String, CaseIterable, Identifiable {
    case transcription = "转写"
    case proofreading = "AI 校对"

    var id: String { rawValue }
}

struct SubtitleSettingsPane: View {
    @Binding var settings: AppSettings
    @ObservedObject var service: SmartServiceStore

    @AppStorage("subforge.customTranscriptionEngine")
    private var storedCustomTranscriptionEngine = TranscriptionEngine.funASRLocal.rawValue
    @State private var customTab: CustomSubtitleTab = .transcription

    private var isOfficial: Bool {
        settings.transcriptionEngine == .officialSmart
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsGroup(title: "字幕方案") {
                VStack(spacing: 12) {
                    planCard(
                        title: "官方（推荐）",
                        subtitle: "无需配置，自动完成转写和 AI 校对",
                        summary: "云端转写 + AI 校对",
                        systemImage: "sparkles.rectangle.stack.fill",
                        selected: isOfficial,
                        action: selectOfficial
                    )

                    planCard(
                        title: "自定义",
                        subtitle: "使用自己的转写和 AI 校对服务",
                        summary: customSummary,
                        systemImage: "slider.horizontal.3",
                        selected: !isOfficial,
                        action: selectCustom
                    )
                }
            }

            if isOfficial {
                OfficialSmartServicePanel(settings: $settings, service: service)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                customSettings
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isOfficial)
        .onAppear(perform: rememberCurrentCustomEngine)
        .onChange(of: settings.transcriptionEngine) { _, engine in
            guard engine != .officialSmart else { return }
            storedCustomTranscriptionEngine = engine.rawValue
        }
    }

    private var customSummary: String {
        let transcription = customTranscriptionEngine.rawValue
        let proofreading = settings.proofreadingEnabled
            ? settings.cloudLLMPreset.rawValue
            : "未配置"
        return "转写：\(transcription)\nAI 校对：\(proofreading)"
    }

    private var customTranscriptionEngine: TranscriptionEngine {
        guard let engine = TranscriptionEngine(rawValue: storedCustomTranscriptionEngine),
              engine != .officialSmart else {
            return .funASRLocal
        }
        return engine
    }

    private var customSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup(title: "自定义设置") {
                Picker("自定义设置", selection: $customTab) {
                    ForEach(CustomSubtitleTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 260)
            }

            switch customTab {
            case .transcription:
                TranscriptionSettingsPane(
                    settings: $settings,
                    allowsOfficialSmart: false
                )
            case .proofreading:
                ProofreadingSettingsPane(settings: $settings)
            }
        }
    }

    private func planCard(
        title: String,
        subtitle: String,
        summary: String,
        systemImage: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .padding(.top, 1)

                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .frame(width: 34, height: 34)
                    .background(
                        (selected ? Color.accentColor : Color.secondary).opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 14)

                Text(summary)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(selected ? .primary : .secondary)
                    .multilineTextAlignment(.trailing)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected ? Color.accentColor.opacity(0.07) : Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        selected ? Color.accentColor.opacity(0.45) : Color(nsColor: .separatorColor).opacity(0.18),
                        lineWidth: selected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel(title)
        .accessibilityValue(selected ? "已选择" : "未选择")
    }

    private func selectOfficial() {
        rememberCurrentCustomEngine()
        settings.transcriptionEngine = .officialSmart
    }

    private func selectCustom() {
        settings.transcriptionEngine = customTranscriptionEngine
    }

    private func rememberCurrentCustomEngine() {
        guard settings.transcriptionEngine != .officialSmart else { return }
        storedCustomTranscriptionEngine = settings.transcriptionEngine.rawValue
    }
}
