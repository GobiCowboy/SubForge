import SwiftUI

struct SmartServiceSettingsPane: View {
    @Binding var settings: AppSettings
    @ObservedObject var service: SmartServiceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            SettingsGroup(title: "智能字幕") {
                SettingsSectionCard(tone: .emphasis) {
                    HStack(alignment: .top, spacing: 18) {
                        Image(systemName: "sparkles.rectangle.stack.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 44, height: 44)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                        VStack(alignment: .leading, spacing: 6) {
                            Text("云端 ASR + AI 校对")
                                .font(.system(size: 17, weight: .semibold))
                            Text("用于正式字幕制作，一次完成转写、时间轴和错字校对。")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)
                        SettingsPill(text: "中国区", tint: .green)
                    }

                    Divider()

                    SettingsKeyValueRow(title: "剩余时长", value: service.balanceText)
                    SettingsKeyValueRow(title: "服务状态", value: service.statusMessage)

                    HStack(spacing: 12) {
                        Button {
                            Task {
                                if await service.purchase300Minutes() {
                                    settings.transcriptionEngine = .officialSmart
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if service.isPurchasing {
                                    ProgressView().controlSize(.small)
                                }
                                Text(purchaseTitle)
                            }
                            .frame(maxWidth: .infinity)
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

                    if service.balanceSeconds > 0, settings.transcriptionEngine != .officialSmart {
                        Button("设为当前转写方式") {
                            settings.transcriptionEngine = .officialSmart
                        }
                        .buttonStyle(.link)
                    }
                }
            }

            SettingsGroup(title: "隐私与计费") {
                SettingsListSection {
                    SettingsListRow(title: "音频路径") {
                        Text("Mac 直传阿里临时 OSS")
                            .foregroundStyle(.secondary)
                    }
                    SettingsListRow(title: "密钥保护") {
                        Text("永久云 Key 仅在服务器")
                            .foregroundStyle(.secondary)
                    }
                    SettingsListRow(title: "计费单位") {
                        Text("按云端返回的实际音频秒数")
                            .foregroundStyle(.secondary)
                    }
                }

                SettingsTipBox(
                    text: "中国区首发：当前不会自动把音频转发到国际区。国际区配置已预留，将在中国区稳定后单独开放。"
                )
            }
        }
        .task { await service.load() }
    }

    private var purchaseTitle: String {
        if service.isPurchasing { return "购买处理中…" }
        if let price = service.productPrice { return "购买 300 分钟 · \(price)" }
        return "购买 300 分钟"
    }
}
