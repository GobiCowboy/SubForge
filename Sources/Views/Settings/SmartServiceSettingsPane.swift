import SwiftUI

/// 官方方案的服务状态与购买区域。
/// 独立成组件，供「字幕方案」页面在官方模式下直接嵌入。
struct SmartServiceSettingsPane: View {
    @Binding var settings: AppSettings
    @ObservedObject var service: SmartServiceStore

    var body: some View {
        OfficialSmartServicePanel(settings: $settings, service: service)
    }
}

struct OfficialSmartServicePanel: View {
    @Binding var settings: AppSettings
    @ObservedObject var service: SmartServiceStore

    @State private var selectedPlan: OfficialPurchasePlan = .standard

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            valueSection
            purchaseSection

            SettingsTipBox(
                text: "购买的时长用于完成转写、时间轴和 AI 校对。音频会上传至云端大模型处理，不会用于研究或数据分析。"
            )
        }
        .task { await service.load() }
    }

    private var valueSection: some View {
        SettingsSectionCard(tone: .emphasis) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    serviceFeature("自动转写", detail: "语音一键变文字", systemImage: "waveform")
                    serviceFeature("精准时间轴", detail: "字幕与画面对齐", systemImage: "timeline.selection")
                    serviceFeature("AI 校对", detail: "修正错别字", systemImage: "wand.and.stars")
                }
            }
        }
    }

    private var purchaseSection: some View {
        SettingsSectionCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("剩余时长")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(service.balanceText)
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }

                    Spacer(minLength: 0)

                    Text("选择套餐")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    ForEach(OfficialServiceConfiguration.purchasePlans) { plan in
                        purchasePlanCard(plan)
                    }
                }

                HStack(spacing: 10) {
                    Spacer(minLength: 0)

                    Button {
                        Task {
                            if await service.purchase(plan: selectedPlan) {
                                settings.transcriptionEngine = .officialSmart
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if service.isPurchasing {
                                ProgressView().controlSize(.small)
                            }
                            Text("购买")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .frame(minWidth: 280, minHeight: 28)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(service.isPurchasing)

                    Button("刷新额度") {
                        Task { await service.refreshWallet() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(service.isLoading || service.isPurchasing)
                }
            }
        }
    }

    private func purchasePlanCard(_ plan: OfficialPurchasePlan) -> some View {
        let isSelected = selectedPlan == plan

        return Button {
            selectedPlan = plan
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                    Text(plan.badge)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                    Spacer(minLength: 0)
                }

                HStack(alignment: .firstTextBaseline) {
                    Text(plan.title)
                        .font(.system(size: 16, weight: .semibold))
                    Spacer(minLength: 8)
                    Text(service.price(for: plan) ?? "价格加载中")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }

                Text("一次购买 · 不自动续费")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.08)
                    : Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? Color.accentColor.opacity(0.75)
                            : Color(nsColor: .separatorColor).opacity(0.18),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(plan.title)
        .accessibilityValue(isSelected ? "已选择，\(plan.badge)" : "未选择")
    }

    private func serviceFeature(_ title: String, detail: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}
