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
        settings.switchSubtitleOrientation(to: orientation)
    }

    private func applyPreset(_ preset: SubtitleStylePreset) {
        settings.subtitleStyle.preset = preset
        settings.subtitleStyle.fontWeight = .semibold
        settings.subtitleStyle.horizontalAlignment = .center
        settings.subtitleStyle.position = .bottom
        settings.subtitleStyle.offsetX = 0
        settings.subtitleStyle.offsetY = settings.subtitleStyle.canvasOrientation == .landscape ? -28 : -84
        settings.subtitleStyle.positionX = 0
        settings.subtitleStyle.positionY = settings.subtitleStyle.canvasOrientation == .landscape ? -500 : -450
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
        WholeNumberField(label: label, value: value)
    }
}

private struct WholeNumberField: View {
    let label: String
    @Binding var value: Double
    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(label: String, value: Binding<Double>) {
        self.label = label
        self._value = value
        self._draft = State(initialValue: Self.stringValue(value.wrappedValue))
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField(label, text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .focused($isFocused)
                .onChange(of: draft) { _, newValue in
                    let sanitized = Self.sanitize(newValue)
                    if sanitized != newValue {
                        draft = sanitized
                    }
                    if let number = Int(sanitized) {
                        value = Double(number)
                    }
                }
                .onChange(of: isFocused) { _, focused in
                    if !focused {
                        commit()
                    }
                }
                .onChange(of: value) { _, newValue in
                    guard !isFocused else { return }
                    let formatted = Self.stringValue(newValue)
                    if draft != formatted {
                        draft = formatted
                    }
                }
                .onSubmit {
                    commit()
                }
                .frame(width: 64)
        }
    }

    private func commit() {
        let number = Int(draft) ?? Int(value.rounded())
        value = Double(number)
        draft = Self.stringValue(value)
    }

    private static func sanitize(_ input: String) -> String {
        let isNegative = input.first == "-"
        let digits = input.filter { $0.isNumber }
        if isNegative {
            return digits.isEmpty ? "-" : "-\(digits)"
        }
        return digits
    }

    private static func stringValue(_ value: Double) -> String {
        String(Int(value.rounded()))
    }
}
