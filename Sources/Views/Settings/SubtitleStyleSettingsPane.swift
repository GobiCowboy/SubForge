import SwiftUI

struct SubtitleStyleSettingsPane: View {
    @Binding var settings: AppSettings

    @State private var textExpanded = true
    @State private var layoutExpanded = true
    @State private var positionExpanded = true
    @State private var fillExpanded = true
    @State private var strokeExpanded = true
    @State private var shadowExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            SettingsGroup(title: "字幕样式") {
                SettingsSectionCard {
                    SubtitleInspectorSection(title: "文本", isExpanded: $textExpanded) {
                        HStack(alignment: .top, spacing: 20) {
                            SubtitleInspectorPickerRow(title: "字体") {
                                Picker("字体", selection: $settings.subtitleStyle.fontFamily) {
                                    Text("苹方-简").tag("PingFang SC")
                                    Text("黑体-简").tag("Heiti SC")
                                    Text("Arial").tag("Arial")
                                }
                                .labelsHidden()
                                .frame(width: 250)
                            }

                            SubtitleInspectorPickerRow(title: "字重") {
                                Picker("字重", selection: $settings.subtitleStyle.fontWeight) {
                                    ForEach(SubtitleFontWeight.allCases) { weight in
                                        Text(weight.rawValue).tag(weight)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 180)
                            }
                        }

                        SubtitleInspectorSliderRow(
                            title: "字号",
                            value: $settings.subtitleStyle.fontSize,
                            range: 20...84,
                            step: 1,
                            display: subtitleInspectorValue(settings.subtitleStyle.fontSize, unit: "pt")
                        )

                        SubtitleInspectorColorRow(
                            title: "文字颜色",
                            value: $settings.subtitleStyle.fontColorHex
                        )
                    }

                    SubtitleInspectorSection(title: "布局", isExpanded: $layoutExpanded) {
                        HStack(alignment: .top, spacing: 20) {
                            SubtitleInspectorPickerRow(title: "水平对齐") {
                                Picker("水平对齐", selection: $settings.subtitleStyle.horizontalAlignment) {
                                    ForEach(SubtitleHorizontalAlignment.allCases) { alignment in
                                        Text(alignment.rawValue.replacingOccurrences(of: "对齐", with: "")).tag(alignment)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                                .frame(width: 220)
                            }

                            SubtitleInspectorPickerRow(title: "垂直对齐") {
                                Picker("垂直对齐", selection: $settings.subtitleStyle.position) {
                                    ForEach(SubtitlePosition.allCases) { position in
                                        Text(position.rawValue).tag(position)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                                .frame(width: 220)
                            }
                        }

                        SubtitleInspectorSliderRow(
                            title: "行高",
                            value: $settings.subtitleStyle.lineSpacing,
                            range: 0...24,
                            step: 1,
                            display: subtitleInspectorValue(settings.subtitleStyle.lineSpacing, unit: "pt")
                        )

                        SubtitleInspectorSliderRow(
                            title: "字距",
                            value: $settings.subtitleStyle.characterSpacing,
                            range: -2...12,
                            step: 0.5,
                            display: subtitleInspectorValue(settings.subtitleStyle.characterSpacing, unit: "pt")
                        )
                    }

                    SubtitleInspectorSection(title: "位置", isExpanded: $positionExpanded) {
                        HStack(alignment: .top, spacing: 20) {
                            SubtitleInspectorNumberFieldRow(
                                title: "X",
                                value: $settings.subtitleStyle.offsetX,
                                unit: "px"
                            )

                            SubtitleInspectorNumberFieldRow(
                                title: "Y",
                                value: $settings.subtitleStyle.offsetY,
                                unit: "px"
                            )
                        }
                    }

                    SubtitleInspectorSection(
                        title: "填充",
                        isExpanded: $fillExpanded,
                        isEnabled: $settings.subtitleStyle.surfaceEnabled
                    ) {
                        if settings.subtitleStyle.surfaceEnabled {
                            SubtitleInspectorColorRow(
                                title: "颜色",
                                value: $settings.subtitleStyle.surfaceColorHex
                            )

                            SubtitleInspectorSliderRow(
                                title: "透明度",
                                value: $settings.subtitleStyle.surfaceOpacity,
                                range: 0...1,
                                step: 0.05,
                                display: subtitleInspectorValue(settings.subtitleStyle.surfaceOpacity * 100, unit: "%")
                            )

                            SubtitleInspectorSliderRow(
                                title: "模糊",
                                value: $settings.subtitleStyle.surfaceBlur,
                                range: 0...12,
                                step: 0.5,
                                display: subtitleInspectorValue(settings.subtitleStyle.surfaceBlur, unit: "px")
                            )
                        }
                    }

                    SubtitleInspectorSection(
                        title: "描边",
                        isExpanded: $strokeExpanded,
                        isEnabled: $settings.subtitleStyle.outlineEnabled
                    ) {
                        if settings.subtitleStyle.outlineEnabled {
                            SubtitleInspectorColorRow(
                                title: "颜色",
                                value: $settings.subtitleStyle.outlineColorHex
                            )

                            SubtitleInspectorSliderRow(
                                title: "透明度",
                                value: $settings.subtitleStyle.outlineOpacity,
                                range: 0...1,
                                step: 0.05,
                                display: subtitleInspectorValue(settings.subtitleStyle.outlineOpacity * 100, unit: "%")
                            )

                            SubtitleInspectorSliderRow(
                                title: "模糊",
                                value: $settings.subtitleStyle.outlineBlur,
                                range: 0...8,
                                step: 0.5,
                                display: subtitleInspectorValue(settings.subtitleStyle.outlineBlur, unit: "px")
                            )

                            SubtitleInspectorSliderRow(
                                title: "宽度",
                                value: $settings.subtitleStyle.outlineWidth,
                                range: 0...8,
                                step: 0.5,
                                display: subtitleInspectorValue(settings.subtitleStyle.outlineWidth, unit: "px")
                            )
                        }
                    }

                    SubtitleInspectorSection(
                        title: "阴影",
                        isExpanded: $shadowExpanded,
                        isEnabled: $settings.subtitleStyle.shadowEnabled
                    ) {
                        if settings.subtitleStyle.shadowEnabled {
                            SubtitleInspectorColorRow(
                                title: "颜色",
                                value: $settings.subtitleStyle.shadowColorHex
                            )

                            SubtitleInspectorSliderRow(
                                title: "透明度",
                                value: $settings.subtitleStyle.shadowOpacity,
                                range: 0...1,
                                step: 0.05,
                                display: subtitleInspectorValue(settings.subtitleStyle.shadowOpacity * 100, unit: "%")
                            )

                            SubtitleInspectorSliderRow(
                                title: "模糊",
                                value: $settings.subtitleStyle.shadowBlur,
                                range: 0...24,
                                step: 0.5,
                                display: subtitleInspectorValue(settings.subtitleStyle.shadowBlur, unit: "px")
                            )
                        }
                    }
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
