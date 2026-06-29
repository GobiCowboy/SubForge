import SwiftUI

struct GeneralSettingsPane: View {
    @Binding var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            SettingsGroup(title: "通用设置") {
                SettingsSectionCard {
                    Picker("界面语言", selection: $settings.interfaceLanguage) {
                        ForEach(InterfaceLanguage.allCases) { language in
                            Text(language.rawValue).tag(language)
                        }
                    }

                    Toggle("显示菜单栏图标", isOn: $settings.showMenuBarIcon)
                }
            }
        }
    }
}
