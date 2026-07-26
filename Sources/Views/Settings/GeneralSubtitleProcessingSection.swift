import SwiftUI

struct GeneralSubtitleProcessingSection: View {
    @Binding var settings: AppSettings

    var body: some View {
        SettingsListSection {
            SettingsListRow(
                title: "单条字幕最大字数",
                controlWidth: 300
            ) {
                SubtitleLengthSlider(settings: $settings)
            }

            SettingsListRow(
                title: "保留标点",
                alignment: .top,
                controlWidth: 300
            ) {
                punctuationControls
            }

            SettingsListRow(
                title: "热词",
                titleDetail: "— 视频中的专有名词、生僻词",
                titleWidth: 220,
                controlWidth: 300
            ) {
                Toggle("", isOn: hotwordEnabledBinding)
                    .labelsHidden()
            }

            SettingsListRow(
                title: "固定热词",
                titleDetail: "— 视频中常用的专有名词、生僻词",
                alignment: .top,
                titleWidth: 245,
                controlWidth: 275
            ) {
                fixedHotwordControls
            }

            SettingsListRow(
                title: "AI 校对提示词",
                alignment: .top,
                controlWidth: 300
            ) {
                settingsTextEditor(text: proofreadingPromptBinding, height: 92)
            }
        }
    }

    private var punctuationControls: some View {
        VStack(alignment: .trailing, spacing: 10) {
            Menu {
                ForEach(SubtitlePunctuationGroup.allCases) { group in
                    Toggle(
                        "\(group.title)  \(group.example)",
                        isOn: punctuationBinding(for: group)
                    )
                }
            } label: {
                Text(punctuationSummary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .menuStyle(.borderlessButton)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    presetButton("不保留标点", groups: [])
                    presetButton(
                        "字幕推荐",
                        groups: SubtitlePunctuationGroup.subtitleRecommended
                    )
                }
                HStack(spacing: 8) {
                    presetButton(
                        "保留结构",
                        groups: SubtitlePunctuationGroup.structural
                    )
                    presetButton(
                        "保留全部",
                        groups: Set(SubtitlePunctuationGroup.allCases)
                    )
                }
            }
        }
    }

    private var fixedHotwordControls: some View {
        VStack(alignment: .trailing, spacing: 10) {
            Toggle("", isOn: fixedHotwordsEnabledBinding)
                .labelsHidden()
            settingsTextEditor(text: fixedHotwordsTextBinding, height: 82)
        }
    }

    private var punctuationSummary: String {
        let groups = settings.effectiveRetainedSubtitlePunctuation
        if groups.isEmpty { return "全部不保留" }
        if groups.count == SubtitlePunctuationGroup.allCases.count { return "保留全部" }
        return "已选 \(groups.count) 项"
    }

    private var hotwordEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.effectiveHotwordPromptPreference == .enabled },
            set: { settings.hotwordPromptPreference = $0 ? .enabled : .disabled }
        )
    }

    private var proofreadingPromptBinding: Binding<String> {
        Binding(
            get: { settings.proofreadingPrompt },
            set: { settings.setProofreadingPrompt($0) }
        )
    }

    private var fixedHotwordsEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.effectiveFixedHotwordsEnabled },
            set: { settings.fixedHotwordsEnabled = $0 }
        )
    }

    private var fixedHotwordsTextBinding: Binding<String> {
        Binding(
            get: { settings.effectiveFixedHotwordsText },
            set: { settings.fixedHotwordsText = $0 }
        )
    }

    private func punctuationBinding(for group: SubtitlePunctuationGroup) -> Binding<Bool> {
        Binding(
            get: { settings.effectiveRetainedSubtitlePunctuation.contains(group) },
            set: { selected in
                var groups = settings.effectiveRetainedSubtitlePunctuation
                if selected {
                    groups.insert(group)
                } else {
                    groups.remove(group)
                }
                settings.retainedSubtitlePunctuation = groups
            }
        )
    }

    private func presetButton(
        _ title: String,
        groups: Set<SubtitlePunctuationGroup>
    ) -> some View {
        let selected = settings.effectiveRetainedSubtitlePunctuation == groups
        return Button {
            settings.retainedSubtitlePunctuation = groups
        } label: {
            Label(
                title,
                systemImage: selected ? "checkmark.circle.fill" : "circle"
            )
            .frame(maxWidth: .infinity)
        }
        .font(.system(size: 12, weight: selected ? .semibold : .medium))
        .foregroundStyle(selected ? Color.accentColor : Color.primary)
        .frame(maxWidth: .infinity, minHeight: 30)
        .background(
            selected
                ? Color.accentColor.opacity(0.15)
                : Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    selected ? Color.accentColor : SettingsVisualTokens.standardBorder,
                    lineWidth: selected ? 1.5 : SettingsVisualTokens.borderWidth
                )
        }
        .buttonStyle(.plain)
    }

    private func settingsTextEditor(
        text: Binding<String>,
        height: CGFloat
    ) -> some View {
        TextEditor(text: text)
            .font(.system(size: 13))
            .frame(height: height)
            .padding(8)
            .background(
                Color(nsColor: .windowBackgroundColor),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        SettingsVisualTokens.standardBorder,
                        lineWidth: SettingsVisualTokens.borderWidth
                    )
            }
    }
}
