import SwiftUI

struct ExportSettingsPane: View {
    @Binding var settings: AppSettings

    private var frameRateBinding: Binding<Int> {
        Binding(
            get: { settings.exportSettings.fps },
            set: { settings.exportSettings.fps = ExportSettings.clampFrameRate($0) }
        )
    }

    var body: some View {
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

            if settings.exportSettings.format.includesFCPXML {
                SettingsListRow(
                    title: "FCPXML 帧率",
                    description: "请与 Final Cut Pro 主工程时间线保持一致，例如 25 fps。"
                ) {
                    HStack(spacing: 8) {
                        Menu {
                            ForEach(ExportSettings.frameRatePresets, id: \.self) { fps in
                                Button("使用 \(fps) fps") {
                                    settings.exportSettings.fps = fps
                                }
                            }
                        } label: {
                            Image(systemName: "list.number")
                        }
                        .menuStyle(.borderlessButton)
                        .help("选择常用帧率")

                        TextField("帧率", value: frameRateBinding, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 64)
                            .accessibilityLabel("FCPXML 帧率")

                        Text("fps")
                            .foregroundStyle(.secondary)
                    }
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
