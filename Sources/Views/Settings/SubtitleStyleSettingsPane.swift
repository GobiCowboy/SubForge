import SwiftUI

struct SubtitleStyleSettingsPane: View {
    @Binding var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            SettingsGroup(title: "样式配置") {
                SettingsSectionCard {
                    Picker("字体", selection: $settings.subtitleStyle.fontFamily) {
                        Text("PingFang SC").tag("PingFang SC")
                        Text("Heiti SC").tag("Heiti SC")
                        Text("Arial").tag("Arial")
                    }

                    HStack(spacing: 16) {
                        HStack {
                            Text("字号")
                            Slider(value: $settings.subtitleStyle.fontSize, in: 28...84, step: 2)
                            Text("\(Int(settings.subtitleStyle.fontSize))")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }

                        Picker("字重", selection: $settings.subtitleStyle.fontWeight) {
                            ForEach(SubtitleFontWeight.allCases) { weight in
                                Text(weight.rawValue).tag(weight)
                            }
                        }
                        .frame(maxWidth: 220)
                    }

                    HStack(spacing: 16) {
                        TextField("文字颜色", text: $settings.subtitleStyle.fontColorHex)
                        TextField("描边颜色", text: $settings.subtitleStyle.outlineColorHex)
                    }

                    HStack(spacing: 16) {
                        HStack {
                            Text("描边宽度")
                            Slider(value: $settings.subtitleStyle.outlineWidth, in: 0...6, step: 0.5)
                            Text(settings.subtitleStyle.outlineWidth, format: .number.precision(.fractionLength(1)))
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }

                        Toggle("启用阴影", isOn: $settings.subtitleStyle.shadowEnabled)
                            .frame(maxWidth: 180)
                    }

                    if settings.subtitleStyle.shadowEnabled {
                        HStack {
                            Text("阴影强度")
                            Slider(value: $settings.subtitleStyle.shadowOpacity, in: 0.1...0.7, step: 0.05)
                            Text(settings.subtitleStyle.shadowOpacity, format: .number.precision(.fractionLength(2)))
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }

                    Picker("位置", selection: $settings.subtitleStyle.position) {
                        ForEach(SubtitlePosition.allCases) { position in
                            Text(position.rawValue).tag(position)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            SettingsGroup(title: "字幕预览") {
                SettingsSectionCard(tone: .emphasis) {
                    SubtitlePreviewCanvas(style: settings.subtitleStyle)
                }
            }
        }
    }
}
