import SwiftUI

struct SubtitleStyleSettingsPane: View {
    @Binding var settings: AppSettings

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { settings.subtitleStyle.fontSize },
            set: { settings.subtitleStyle.fontSize = min(max($0.rounded(), 12), 120) }
        )
    }

    private var positionXBinding: Binding<Double> {
        Binding(
            get: { settings.subtitleStyle.positionX },
            set: { settings.subtitleStyle.positionX = $0.rounded() }
        )
    }

    private var positionYBinding: Binding<Double> {
        Binding(
            get: { settings.subtitleStyle.positionY },
            set: { settings.subtitleStyle.positionY = $0.rounded() }
        )
    }

    private var positionZBinding: Binding<Double> {
        Binding(
            get: { settings.subtitleStyle.positionZ },
            set: { settings.subtitleStyle.positionZ = $0.rounded() }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            SettingsGroup(title: "基本样式") {
                SettingsListSection {
                    SettingsListRow(title: "画幅") {
                        HStack(spacing: 0) {
                            ForEach(SubtitleCanvasOrientation.allCases) { orientation in
                                orientationButton(orientation)
                            }
                        }
                        .padding(3)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .frame(width: SettingsListMetrics.pickerWidth, alignment: .trailing)
                    }

                    SettingsListRow(title: "字体") {
                        SettingsTrailingControl {
                            Picker("字体", selection: $settings.subtitleStyle.fontFamily) {
                                Text("苹方-简").tag("PingFang SC")
                                Text("黑体-简").tag("Heiti SC")
                                Text("Arial").tag("Arial")
                            }
                            .labelsHidden()
                        }
                    }

                    SettingsListRow(title: "字号") {
                        HStack(spacing: 12) {
                            Text("\(Int(settings.subtitleStyle.fontSize.rounded())) pt")
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .frame(width: 64, alignment: .trailing)

                            Stepper("", value: fontSizeBinding, in: 12...120, step: 1)
                                .labelsHidden()
                        }
                        .frame(width: SettingsListMetrics.pickerWidth, alignment: .trailing)
                    }

                    SettingsListRow(title: "位置") {
                        HStack(spacing: 8) {
                            positionField("X", value: positionXBinding)
                            positionField("Y", value: positionYBinding)
                            positionField("Z", value: positionZBinding)
                        }
                        .frame(width: SettingsListMetrics.controlWidth, alignment: .trailing)
                    }

                    SettingsListRow(title: "预设", alignment: .center) {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.fixed(92), spacing: 8), count: 3),
                            alignment: .trailing,
                            spacing: 8
                        ) {
                            ForEach(SubtitleStylePreset.allCases) { preset in
                                SubtitlePresetButton(
                                    preset: preset,
                                    isSelected: settings.subtitleStyle.preset == preset
                                ) {
                                    applyPreset(preset)
                                }
                            }
                        }
                        .frame(width: SettingsListMetrics.controlWidth, alignment: .trailing)
                    }
                }
            }
        }
        .onAppear(perform: syncPresetFromCurrentStyle)
    }

    private func orientationButton(_ orientation: SubtitleCanvasOrientation) -> some View {
        let isSelected = settings.subtitleStyle.canvasOrientation == orientation

        return Button {
            applyOrientation(orientation)
        } label: {
            Text(orientation.rawValue)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    private func applyOrientation(_ orientation: SubtitleCanvasOrientation) {
        settings.subtitleStyle.canvasOrientation = orientation
        settings.subtitleStyle.position = .bottom
        settings.subtitleStyle.offsetX = 0
        settings.subtitleStyle.offsetY = orientation == .landscape ? -28 : -84
        settings.subtitleStyle.positionX = 0
        settings.subtitleStyle.positionY = orientation == .landscape ? -467 : -495
        settings.subtitleStyle.positionZ = 0
        settings.subtitleStyle.fontSize = orientation == .landscape ? 56 : 35
    }

    private func applyPreset(_ preset: SubtitleStylePreset) {
        settings.subtitleStyle.preset = preset
        settings.subtitleStyle.fontWeight = .semibold
        settings.subtitleStyle.horizontalAlignment = .center
        settings.subtitleStyle.position = .bottom
        settings.subtitleStyle.offsetX = 0
        settings.subtitleStyle.offsetY = settings.subtitleStyle.canvasOrientation == .landscape ? -28 : -84
        settings.subtitleStyle.positionX = 0
        settings.subtitleStyle.positionY = settings.subtitleStyle.canvasOrientation == .landscape ? -467 : -495
        settings.subtitleStyle.positionZ = 0
        settings.subtitleStyle.lineSpacing = 0
        settings.subtitleStyle.characterSpacing = 0
        settings.subtitleStyle.shadowEnabled = false
        settings.subtitleStyle.shadowOpacity = 0.35
        settings.subtitleStyle.shadowBlur = 10
        settings.subtitleStyle.shadowOffsetY = 4

        switch preset {
        case .whiteTextBlackOutline:
            settings.subtitleStyle.fontColorHex = "#FFFFFF"
            settings.subtitleStyle.outlineEnabled = true
            settings.subtitleStyle.outlineColorHex = "#111111"
            settings.subtitleStyle.outlineOpacity = 1
            settings.subtitleStyle.outlineBlur = 0
            settings.subtitleStyle.outlineWidth = 2
            settings.subtitleStyle.surfaceEnabled = false
            settings.subtitleStyle.surfaceColorHex = "#111111"
            settings.subtitleStyle.surfaceOpacity = 0.72
            settings.subtitleStyle.surfaceBlur = 0
        case .blackTextWhiteOutline:
            settings.subtitleStyle.fontColorHex = "#111111"
            settings.subtitleStyle.outlineEnabled = true
            settings.subtitleStyle.outlineColorHex = "#FFFFFF"
            settings.subtitleStyle.outlineOpacity = 1
            settings.subtitleStyle.outlineBlur = 0
            settings.subtitleStyle.outlineWidth = 2
            settings.subtitleStyle.surfaceEnabled = false
            settings.subtitleStyle.surfaceColorHex = "#FFFFFF"
            settings.subtitleStyle.surfaceOpacity = 0.72
            settings.subtitleStyle.surfaceBlur = 0
        case .whiteTextDarkFill:
            settings.subtitleStyle.fontColorHex = "#FFFFFF"
            settings.subtitleStyle.outlineEnabled = false
            settings.subtitleStyle.outlineColorHex = "#111111"
            settings.subtitleStyle.outlineOpacity = 1
            settings.subtitleStyle.outlineBlur = 0
            settings.subtitleStyle.outlineWidth = 0
            settings.subtitleStyle.surfaceEnabled = true
            settings.subtitleStyle.surfaceColorHex = "#111111"
            settings.subtitleStyle.surfaceOpacity = 0.72
            settings.subtitleStyle.surfaceBlur = 0
        case .yellowTextBlackOutline:
            settings.subtitleStyle.fontColorHex = "#FFD84D"
            settings.subtitleStyle.outlineEnabled = true
            settings.subtitleStyle.outlineColorHex = "#111111"
            settings.subtitleStyle.outlineOpacity = 1
            settings.subtitleStyle.outlineBlur = 0
            settings.subtitleStyle.outlineWidth = 2
            settings.subtitleStyle.surfaceEnabled = false
            settings.subtitleStyle.surfaceColorHex = "#111111"
            settings.subtitleStyle.surfaceOpacity = 0.72
            settings.subtitleStyle.surfaceBlur = 0
        case .whiteTextBlueFill:
            settings.subtitleStyle.fontColorHex = "#FFFFFF"
            settings.subtitleStyle.outlineEnabled = false
            settings.subtitleStyle.outlineColorHex = "#111111"
            settings.subtitleStyle.outlineOpacity = 1
            settings.subtitleStyle.outlineBlur = 0
            settings.subtitleStyle.outlineWidth = 0
            settings.subtitleStyle.surfaceEnabled = true
            settings.subtitleStyle.surfaceColorHex = "#1358D6"
            settings.subtitleStyle.surfaceOpacity = 0.82
            settings.subtitleStyle.surfaceBlur = 0
        }
    }

    private func syncPresetFromCurrentStyle() {
        if settings.subtitleStyle.surfaceEnabled {
            if settings.subtitleStyle.surfaceColorHex.uppercased() == "#1358D6" {
                settings.subtitleStyle.preset = .whiteTextBlueFill
            } else {
                settings.subtitleStyle.preset = .whiteTextDarkFill
            }
            return
        }

        if settings.subtitleStyle.fontColorHex.uppercased() == "#FFD84D",
           settings.subtitleStyle.outlineEnabled,
           settings.subtitleStyle.outlineColorHex.uppercased() == "#111111" {
            settings.subtitleStyle.preset = .yellowTextBlackOutline
            return
        }

        if settings.subtitleStyle.fontColorHex.uppercased() == "#111111",
           settings.subtitleStyle.outlineEnabled,
           settings.subtitleStyle.outlineColorHex.uppercased() == "#FFFFFF" {
            settings.subtitleStyle.preset = .blackTextWhiteOutline
            return
        }

        settings.subtitleStyle.preset = .whiteTextBlackOutline
    }

    private func positionField(_ label: String, value: Binding<Double>) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField(label, value: value, format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 64)
        }
    }
}

private struct SubtitlePresetButton: View {
    private struct TextOffset: Identifiable {
        let id: Int
        let size: CGSize
    }

    let preset: SubtitleStylePreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                presetSample

                Text(preset.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .frame(width: 92, height: 74)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.10) : Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected ? SettingsVisualTokens.selectedBorder : SettingsVisualTokens.choiceBorder,
                        lineWidth: SettingsVisualTokens.borderWidth
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var presetSample: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))

            if presetUsesFill {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(fillColor)
                    .frame(width: 44, height: 30)
            }

            outlinedText
        }
        .frame(width: 54, height: 34)
    }

    private var outlinedText: some View {
        ZStack {
            if !presetUsesFill {
                ForEach(outlineOffsets) { offset in
                    Text("Aa")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(strokeColor)
                        .offset(offset.size)
                }
            }

            Text("Aa")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(textColor)
        }
    }

    private var outlineOffsets: [TextOffset] {
        [
            CGSize(width: -1.2, height: 0),
            CGSize(width: 1.2, height: 0),
            CGSize(width: 0, height: -1.2),
            CGSize(width: 0, height: 1.2),
            CGSize(width: -1.2, height: -1.2),
            CGSize(width: 1.2, height: -1.2),
            CGSize(width: -1.2, height: 1.2),
            CGSize(width: 1.2, height: 1.2)
        ].enumerated().map { TextOffset(id: $0.offset, size: $0.element) }
    }

    private var textColor: Color {
        switch preset {
        case .whiteTextBlackOutline, .whiteTextDarkFill, .whiteTextBlueFill:
            return .white
        case .blackTextWhiteOutline:
            return Color(hexLiteral: "#111111")
        case .yellowTextBlackOutline:
            return Color(hexLiteral: "#FFD84D")
        }
    }

    private var strokeColor: Color {
        switch preset {
        case .whiteTextBlackOutline, .yellowTextBlackOutline:
            return Color(hexLiteral: "#111111")
        case .blackTextWhiteOutline:
            return .white
        case .whiteTextDarkFill, .whiteTextBlueFill:
            return .clear
        }
    }

    private var fillColor: Color {
        switch preset {
        case .whiteTextDarkFill:
            return Color(hexLiteral: "#111111").opacity(0.82)
        case .whiteTextBlueFill:
            return Color(hexLiteral: "#1358D6").opacity(0.82)
        default:
            return .clear
        }
    }

    private var presetUsesFill: Bool {
        switch preset {
        case .whiteTextDarkFill, .whiteTextBlueFill:
            return true
        default:
            return false
        }
    }
}

private extension Color {
    init(hexLiteral: String) {
        self = colorFromHex(hexLiteral)
    }
}
