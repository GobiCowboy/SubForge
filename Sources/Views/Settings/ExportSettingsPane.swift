import SwiftUI

struct ExportSettingsPane: View {
    @Binding var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            SettingsGroup(title: "导出配置") {
                SettingsListSection {
                    SettingsListRow(title: "导出格式") {
                        SettingsTrailingControl {
                            Picker("导出格式", selection: $settings.exportSettings.format) {
                                Text("SRT").tag(ExportFormat.srt)
                                Text("FCPXML").tag(ExportFormat.fcpxml)
                                Text("SRT + FCPXML").tag(ExportFormat.srtAndFCPXML)
                            }
                            .labelsHidden()
                        }
                    }

                    SettingsListRow(
                        title: "导出到 FCP",
                        description: "导出 FCPXML 后自动打开 Final Cut Pro 并导入。"
                    ) {
                        Toggle("", isOn: $settings.exportSettings.exportToFinalCutPro)
                            .labelsHidden()
                    }

                    SettingsListRow(title: "保存位置") {
                        SettingsTrailingControl {
                            Picker("保存位置", selection: $settings.exportSettings.saveLocation) {
                                ForEach(SaveLocation.allCases) { location in
                                    Text(location.rawValue).tag(location)
                                }
                            }
                            .labelsHidden()
                        }
                    }

                    if settings.exportSettings.saveLocation == .customFolder {
                        SettingsListRow(title: "自定义目录") {
                            HStack(spacing: 8) {
                                TextField("请选择目录", text: $settings.exportSettings.customOutputPath)
                                    .textFieldStyle(.roundedBorder)

                                Button("选择…") {
                                    chooseDirectory(
                                        for: $settings.exportSettings.customOutputPath,
                                        bookmarkData: $settings.exportSettings.customOutputBookmarkData
                                    )
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }

                    SettingsListRow(title: "自动覆盖") {
                        Toggle("", isOn: $settings.exportSettings.overwriteExisting)
                            .labelsHidden()
                    }
                }
            }
        }
    }
}
