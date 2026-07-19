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
        VStack(alignment: .leading, spacing: 14) {
            SettingsGroup(title: "智能字幕") {
                SettingsSectionCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "sparkles.rectangle.stack.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 38, height: 38)
                                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                            VStack(alignment: .leading, spacing: 4) {
                                Text("ASR + AI 校对")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("一次处理，直接得到可用字幕")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 0)
                        }

                        HStack(spacing: 8) {
                            serviceFeaturePill("自动转写", systemImage: "waveform")
                            serviceFeaturePill("时间轴", systemImage: "timeline.selection")
                            serviceFeaturePill("AI 校对", systemImage: "wand.and.stars")
                        }
                    }

                    Divider()

                    HStack(alignment: .bottom, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("剩余时长")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(service.balanceText)
                                .font(.system(size: 26, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                        }

                        Spacer(minLength: 0)

                        HStack(spacing: 8) {
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
                            .controlSize(.regular)
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

            SettingsTipBox(
                text: "选择音频后，SubForge 会自动完成转写、时间轴和 AI 校对。"
            )
        }
        .task { await service.load() }
    }

    private var purchaseTitle: String {
        if service.isPurchasing { return "购买处理中…" }
        if let price = service.productPrice { return "购买 300 分钟 · \(price)" }
        return "购买 300 分钟"
    }

    private func serviceFeaturePill(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
