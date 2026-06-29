import SwiftUI

struct ExportSettingsPane: View {
    @Binding var settings: AppSettings

    private var exportLocationSummary: String {
        switch settings.exportSettings.saveLocation {
        case .sameAsSource:
            "与源文件同目录"
        case .customFolder:
            settings.exportSettings.customOutputPath.isEmpty ? "未指定目录" : settings.exportSettings.customOutputPath
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            SettingsGroup(title: "导出配置") {
                SettingsSectionCard {
                    Picker("导出格式", selection: $settings.exportSettings.format) {
                        ForEach(ExportFormat.allCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }

                    HStack(spacing: 16) {
                        Picker("帧率", selection: $settings.exportSettings.fps) {
                            Text("23.976").tag(24)
                            Text("25").tag(25)
                            Text("29.97").tag(30)
                            Text("60").tag(60)
                        }

                        TextField("宽", value: $settings.exportSettings.width, format: .number)
                        TextField("高", value: $settings.exportSettings.height, format: .number)
                    }

                    TextField("文件命名规则", text: $settings.exportSettings.namingRule)

                    Picker("保存位置", selection: $settings.exportSettings.saveLocation) {
                        ForEach(SaveLocation.allCases) { location in
                            Text(location.rawValue).tag(location)
                        }
                    }

                    if settings.exportSettings.saveLocation == .customFolder {
                        SettingsPathField(title: "自定义目录", path: $settings.exportSettings.customOutputPath)
                    }

                    Toggle("自动覆盖同名文件", isOn: $settings.exportSettings.overwriteExisting)
                    Toggle("导出附加日志", isOn: $settings.exportSettings.includeLog)
                }
            }

            SettingsGroup(title: "输出摘要") {
                SettingsSectionCard(tone: .emphasis) {
                    SettingsKeyValueRow(title: "格式", value: settings.exportSettings.format.rawValue)
                    SettingsKeyValueRow(title: "帧率", value: "\(settings.exportSettings.fps) fps")
                    SettingsKeyValueRow(title: "分辨率", value: "\(settings.exportSettings.width) × \(settings.exportSettings.height)")
                    SettingsKeyValueRow(title: "命名规则", value: settings.exportSettings.namingRule)
                    SettingsKeyValueRow(title: "保存位置", value: exportLocationSummary)
                    SettingsKeyValueRow(
                        title: "附加产物",
                        value: settings.exportSettings.includeLog ? "字幕文件 + 处理日志" : "仅字幕文件"
                    )
                }
            }
        }
    }
}
