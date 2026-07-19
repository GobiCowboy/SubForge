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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSectionCard(tone: .emphasis) {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 44, height: 44)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 5) {
                        Text("官方智能字幕")
                            .font(.system(size: 17, weight: .semibold))
                        Text("无需配置，自动完成转写、时间轴和 AI 校对")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                    SettingsPill(text: "即开即用", tint: .green)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    serviceFeatureRow("自动转写")
                    serviceFeatureRow("自动生成时间轴")
                    serviceFeatureRow("自动 AI 校对")
                }

                Divider()

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("剩余时长")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(service.balanceText)
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }

                    Spacer(minLength: 16)

                    HStack(spacing: 10) {
                        Button {
                            Task {
                                _ = await service.purchase300Minutes()
                                settings.transcriptionEngine = .officialSmart
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if service.isPurchasing {
                                    ProgressView().controlSize(.small)
                                }
                                Text(purchaseTitle)
                            }
                            .frame(minWidth: 154)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(service.isPurchasing)

                        Button("刷新额度") {
                            Task { await service.refreshWallet() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(service.isLoading || service.isPurchasing)
                    }
                }
            }

            SettingsTipBox(
                text: "使用云端智能字幕时，音频和字幕仅用于完成本次转写与校对，不用于模型训练或研究。"
            )
        }
        .task { await service.load() }
    }

    private var purchaseTitle: String {
        if service.isPurchasing { return "购买处理中…" }
        if let price = service.productPrice { return "购买 300 分钟 · \(price)" }
        return "购买 300 分钟"
    }

    private func serviceFeatureRow(_ text: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(text)
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(.primary)
    }
}
