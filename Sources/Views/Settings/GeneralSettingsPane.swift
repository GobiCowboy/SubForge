import SwiftUI

struct GeneralSettingsPane: View {
    @Binding var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSubsectionHeader(title: "应用")

            SettingsListSection {
                SettingsListRow(title: "界面语言") {
                    SettingsTrailingControl {
                        Picker("界面语言", selection: $settings.interfaceLanguage) {
                            ForEach(InterfaceLanguage.allCases) { language in
                                Text(language.rawValue).tag(language)
                            }
                        }
                        .labelsHidden()
                    }
                }

                SettingsListRow(title: "菜单栏图标") {
                    Toggle("", isOn: $settings.showMenuBarIcon)
                        .labelsHidden()
                }
            }

            SettingsSubsectionHeader(title: "字幕处理")
                .padding(.top, 10)

            GeneralSubtitleProcessingSection(settings: $settings)
        }
    }
}
