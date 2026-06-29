import SwiftUI

struct SubtitleStyleSettingsPane: View {
    @Binding var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            SettingsGroup(title: "样式配置") {
                SettingsSectionCard {
                    sectionLabel("基本")

                    HStack(spacing: 16) {
                        Picker("字体", selection: $settings.subtitleStyle.fontFamily) {
                            Text("苹方-简").tag("PingFang SC")
                            Text("黑体-简").tag("Heiti SC")
                            Text("Arial").tag("Arial")
                        }
                        .font(.system(size: 12))

                        Picker("字重", selection: $settings.subtitleStyle.fontWeight) {
                            ForEach(SubtitleFontWeight.allCases) { weight in
                                Text(weight.rawValue).tag(weight)
                            }
                        }
                        .font(.system(size: 12))
                        .frame(maxWidth: 180)
                    }

                    sliderRow(
                        title: "大小",
                        value: $settings.subtitleStyle.fontSize,
                        range: 20...84,
                        step: 1,
                        display: "\(Int(settings.subtitleStyle.fontSize))"
                    )

                    Picker("对齐", selection: $settings.subtitleStyle.horizontalAlignment) {
                        ForEach(SubtitleHorizontalAlignment.allCases) { alignment in
                            Text(alignment.rawValue).tag(alignment)
                        }
                    }
                    .font(.system(size: 12))
                    .pickerStyle(.segmented)

                    Picker("垂直对齐", selection: $settings.subtitleStyle.position) {
                        ForEach(SubtitlePosition.allCases) { position in
                            Text(position.rawValue).tag(position)
                        }
                    }
                    .font(.system(size: 12))
                    .pickerStyle(.segmented)

                    sliderRow(
                        title: "行间距",
                        value: $settings.subtitleStyle.lineSpacing,
                        range: 0...24,
                        step: 1,
                        display: "\(Int(settings.subtitleStyle.lineSpacing))"
                    )

                    sliderRow(
                        title: "字距",
                        value: $settings.subtitleStyle.characterSpacing,
                        range: -2...12,
                        step: 0.5,
                        display: "\(Int(settings.subtitleStyle.characterSpacing.rounded()))%"
                    )

                    sectionSpacing
                    sectionLabel("位置")

                    HStack(spacing: 16) {
                        sliderRow(
                            title: "X",
                            value: $settings.subtitleStyle.offsetX,
                            range: -240...240,
                            step: 2,
                            display: "\(Int(settings.subtitleStyle.offsetX)) px"
                        )

                        sliderRow(
                            title: "Y",
                            value: $settings.subtitleStyle.offsetY,
                            range: -240...120,
                            step: 2,
                            display: "\(Int(settings.subtitleStyle.offsetY)) px"
                        )
                    }

                    sectionSpacing
                    styleToggleHeader(title: "表面", isOn: $settings.subtitleStyle.surfaceEnabled)

                    if settings.subtitleStyle.surfaceEnabled {
                        colorRow(title: "颜色", text: $settings.subtitleStyle.surfaceColorHex)

                        sliderRow(
                            title: "不透明度",
                            value: $settings.subtitleStyle.surfaceOpacity,
                            range: 0...1,
                            step: 0.05,
                            display: "\(Int(settings.subtitleStyle.surfaceOpacity * 100))%"
                        )

                        sliderRow(
                            title: "模糊",
                            value: $settings.subtitleStyle.surfaceBlur,
                            range: 0...12,
                            step: 0.5,
                            display: settings.subtitleStyle.surfaceBlur.formatted(.number.precision(.fractionLength(1)))
                        )
                    }

                    sectionSpacing
                    styleToggleHeader(title: "外框", isOn: $settings.subtitleStyle.outlineEnabled)

                    if settings.subtitleStyle.outlineEnabled {
                        colorRow(title: "颜色", text: $settings.subtitleStyle.outlineColorHex)

                        sliderRow(
                            title: "不透明度",
                            value: $settings.subtitleStyle.outlineOpacity,
                            range: 0...1,
                            step: 0.05,
                            display: "\(Int(settings.subtitleStyle.outlineOpacity * 100))%"
                        )

                        sliderRow(
                            title: "模糊",
                            value: $settings.subtitleStyle.outlineBlur,
                            range: 0...8,
                            step: 0.5,
                            display: settings.subtitleStyle.outlineBlur.formatted(.number.precision(.fractionLength(1)))
                        )

                        sliderRow(
                            title: "宽度",
                            value: $settings.subtitleStyle.outlineWidth,
                            range: 0...8,
                            step: 0.5,
                            display: settings.subtitleStyle.outlineWidth.formatted(.number.precision(.fractionLength(1)))
                        )
                    }

                    sectionSpacing
                    colorRow(title: "文字颜色", text: $settings.subtitleStyle.fontColorHex)
                }
            }

            SettingsGroup(title: "字幕预览") {
                SettingsSectionCard(tone: .emphasis) {
                    SubtitlePreviewCanvas(style: settings.subtitleStyle)
                }
            }
        }
    }

    private var sectionSpacing: some View {
        Color.clear
            .frame(height: 4)
    }

    private func sectionLabel(_ title: String) -> some View {
        SettingsSubsectionHeader(title: title)
    }

    private func styleToggleHeader(title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            SettingsSubsectionHeader(title: title)
        }
        .toggleStyle(.switch)
    }

    private func colorRow(title: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)

            TextField("#FFFFFF", text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(colorFromHex(text.wrappedValue))
                .frame(width: 34, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12))
                )
        }
    }

    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        display: String
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)

            Slider(value: value, in: range, step: step)

            Text(display)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .trailing)
        }
    }
}
