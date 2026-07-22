import SwiftUI

struct SettingsSidebar: View {
    @Binding var selection: SettingsSection
    let selectedSubtitlePlan: SubtitlePlan
    let onSelectSubtitlePlan: (SubtitlePlan) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("设置")
                .font(.system(size: 17, weight: .semibold))
                .padding(.top, 22)
                .padding(.horizontal, 20)
                .padding(.bottom, 22)

            VStack(alignment: .leading, spacing: 6) {
                sidebarButton(.general)
                subtitlePlanGroup
                ForEach([SettingsSection.style, .export, .watch]) { section in
                    sidebarButton(section)
                }
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 0)
        }
        .frame(width: 240, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
    }

    private var subtitlePlanGroup: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Image(systemName: SettingsSection.subtitles.icon)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 20, alignment: .center)

                Text(SettingsSection.subtitles.rawValue)
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.top, 16)
            .padding(.bottom, 4)

            ForEach(SubtitlePlan.allCases) { plan in
                subtitlePlanButton(plan)
            }
        }
    }

    private func sidebarButton(_ section: SettingsSection) -> some View {
        HStack(spacing: 10) {
            Image(systemName: section.icon)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 20, alignment: .center)

            Text(section.rawValue)
                .font(.system(size: 15, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .foregroundStyle(selection == section ? Color.white : Color.primary)
        .padding(.horizontal, 12)
        .frame(width: 216, height: 38, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selection == section ? Color.accentColor : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            selection = section
        }
    }

    private func subtitlePlanButton(_ plan: SubtitlePlan) -> some View {
        let isSelected = selectedSubtitlePlan == plan
        let isCurrentPage = isSelected && selection == .subtitles

        return Button {
            onSelectSubtitlePlan(plan)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 16, alignment: .center)
                    .foregroundStyle(isCurrentPage ? Color.white : (isSelected ? Color.accentColor : .secondary))

                Text(plan.title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)

                if let badge = plan.badge {
                    planBadge(badge, isCurrentPage: isCurrentPage)
                }

                Spacer(minLength: 0)
            }
            .foregroundStyle(isCurrentPage ? Color.white : Color.primary)
            .padding(.leading, 38)
            .padding(.trailing, 12)
            .frame(width: 216, height: 34, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isCurrentPage ? Color.accentColor : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityLabel(plan.title)
        .accessibilityValue(isSelected ? "已选择" : "未选择")
    }

    private func planBadge(_ text: String, isCurrentPage: Bool) -> some View {
        let isRecommended = text == "推荐"
        let tint: Color = isRecommended ? .accentColor : .secondary

        return Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                isCurrentPage ? Color.white : tint.opacity(0.11),
                in: Capsule()
            )
    }
}
