import SwiftUI

struct WatchSettingsPane: View {
    @Binding var settings: AppSettings

    private var lastScanSummary: String {
        Date.now.addingTimeInterval(-320).formatted(date: .abbreviated, time: .shortened)
    }

    private var watchLogLines: [String] {
        [
            "发现新素材：marketing_v3.mp4",
            settings.watchSettings.manualReviewBeforeExport ? "已进入人工复核队列" : "已自动进入导出流程",
            "错误提醒方式：\(settings.watchSettings.errorNotice.rawValue)"
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            SettingsGroup(title: "监听配置") {
                SettingsSectionCard {
                    SettingsPathField(title: "监听目录", path: $settings.watchSettings.directoryPath)
                    Toggle("应用启动时自动开始监听", isOn: $settings.watchSettings.autoStart)
                    Toggle("导出前要求人工复核", isOn: $settings.watchSettings.manualReviewBeforeExport)

                    Picker("新文件动作", selection: $settings.watchSettings.newFileAction) {
                        ForEach(WatchAction.allCases) { action in
                            Text(action.rawValue).tag(action)
                        }
                    }

                    Picker("错误提醒方式", selection: $settings.watchSettings.errorNotice) {
                        ForEach(ErrorNotice.allCases) { notice in
                            Text(notice.rawValue).tag(notice)
                        }
                    }
                }
            }

            SettingsGroup(title: "状态 / 日志摘要") {
                SettingsSectionCard(tone: .emphasis) {
                    SettingsKeyValueRow(
                        title: "当前状态",
                        value: settings.watchSettings.autoStart ? "正在监听" : "待启动",
                        tint: settings.watchSettings.autoStart ? .green : .secondary
                    )
                    SettingsKeyValueRow(title: "最近扫描", value: lastScanSummary)
                    SettingsKeyValueRow(
                        title: "目录",
                        value: settings.watchSettings.directoryPath.isEmpty ? "尚未指定" : settings.watchSettings.directoryPath
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        Text("最近事件")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)

                        ForEach(watchLogLines, id: \.self) { line in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.6))
                                    .frame(width: 7, height: 7)
                                    .padding(.top, 6)
                                Text(line)
                                    .font(.system(size: 14))
                            }
                        }
                    }
                }
            }
        }
    }
}
