import SwiftUI

struct WatchSettingsPane: View {
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
                                chooseDirectory(for: $settings.watchSettings.directoryPath)
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
                }
            }
        }
    }
}
