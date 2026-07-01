import SwiftUI

struct WatchSettingsPane: View {
    @EnvironmentObject private var model: AppModel
    @Binding var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            SettingsGroup(title: "目录监听") {
                SettingsListSection {
                    SettingsListRow(title: "监听目录") {
                        HStack(spacing: 8) {
                            TextField("请选择目录", text: $settings.watchSettings.directoryPath)
                                .textFieldStyle(.roundedBorder)

                            Button("选择…") {
                                chooseDirectory(
                                    for: $settings.watchSettings.directoryPath,
                                    bookmarkData: $settings.watchSettings.directoryBookmarkData
                                )
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    SettingsListRow(title: "自动监听") {
                        Toggle("", isOn: $settings.watchSettings.autoStart)
                            .labelsHidden()
                    }

                    SettingsListRow(title: "人工复核") {
                        Toggle("", isOn: $settings.watchSettings.manualReviewBeforeExport)
                            .labelsHidden()
                    }

                    SettingsListRow(
                        title: "监听状态",
                        description: model.watchStatusMessage
                    ) {
                        if model.isWatchingDirectory {
                            Button("停止监听") {
                                model.stopWatchFolder()
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button("开始监听") {
                                model.startWatchFolder()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(settings.watchSettings.directoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }

                    SettingsListRow(title: "已处理") {
                        Text("\(model.watchedFileCount) 个文件")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
