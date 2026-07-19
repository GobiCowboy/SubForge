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
    @State private var isSegmentationExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            valueSection
            Divider()
            segmentationSection
            Divider()
            purchaseSection
            privacyNotice
        }
        .task { await service.load() }
    }

    private var valueSection: some View {
        HStack(spacing: 20) {
            serviceFeature("自动转写", systemImage: "waveform")
            serviceFeature("精准时间轴", systemImage: "timeline.selection")
            serviceFeature("AI 校对", systemImage: "wand.and.stars")
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var purchaseSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("剩余时长")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(service.balanceText)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }

                Spacer(minLength: 0)

                Text("选择套餐")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
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
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(minWidth: 112, minHeight: 20)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(service.isPurchasing)

                Button("刷新额度") {
                    Task { await service.refreshWallet() }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(service.isLoading || service.isPurchasing)
            }
            .padding(.top, 18)

            Label(purchaseStatusText, systemImage: purchaseStatusIcon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(purchaseStatusColor)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.top, 26)
    }

    private var segmentationSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("字幕分段")
                    .font(.system(size: 13, weight: .semibold))

                Spacer(minLength: 0)

                Text("每条最多 \(settings.effectiveMaxSubtitleLength(for: .official)) 字")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Button(isSegmentationExpanded ? "收起" : "调整") {
                    isSegmentationExpanded.toggle()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if isSegmentationExpanded {
                SubtitleLengthSlider(settings: $settings, profile: .official)
                    .padding(.top, 14)
            }
        }
        .padding(.vertical, 14)
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
                    Text(service.priceText(for: plan))
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }

                Text("一次购买 · 不自动续费")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? SettingsVisualTokens.selectedBorder
                            : SettingsVisualTokens.choiceBorder,
                        lineWidth: isSelected ? 1.25 : SettingsVisualTokens.borderWidth
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(plan.title)
        .accessibilityValue(isSelected ? "已选择，\(plan.badge)" : "未选择")
    }

    private func serviceFeature(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(title)
                .font(.system(size: 13, weight: .semibold))

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var privacyNotice: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "info.circle")
                .foregroundStyle(Color.accentColor)
            Text("购买的时长用于完成转写、时间轴和 AI 校对。音频会上传至云端大模型处理，不会用于研究或数据分析。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
        }
        .padding(.top, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var purchaseStatusText: String {
        if service.isPurchasing { return service.statusMessage }
        return service.productCatalogMessage ?? service.statusMessage
    }

    private var purchaseStatusIcon: String {
        if service.isPurchasing { return "hourglass" }
        if purchaseStatusIsError { return "exclamationmark.triangle.fill" }
        return "checkmark.circle.fill"
    }

    private var purchaseStatusColor: Color {
        if service.isPurchasing { return .accentColor }
        if purchaseStatusIsError { return .orange }
        return .secondary
    }

    private var purchaseStatusIsError: Bool {
        if service.productCatalogMessage != nil { return true }
        return ["错误", "失败", "无法", "不可用"].contains { service.statusMessage.contains($0) }
    }

}
