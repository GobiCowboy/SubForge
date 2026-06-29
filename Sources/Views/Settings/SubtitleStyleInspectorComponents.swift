import SwiftUI

struct SubtitleInspectorSection<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    var isEnabled: Binding<Bool>? = nil
    @ViewBuilder let content: Content

    init(
        title: String,
        isExpanded: Binding<Bool>,
        isEnabled: Binding<Bool>? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self._isExpanded = isExpanded
        self.isEnabled = isEnabled
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button(action: { isExpanded.toggle() }) {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 10)

                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                if let isEnabled {
                    Toggle("", isOn: isEnabled)
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    content
                }
                .padding(.top, 12)
                .padding(.leading, 18)
            }
        }
    }
}

struct SubtitleInspectorSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let display: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(display)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
            }

            Slider(value: $value, in: range, step: step)
                .frame(width: 260)
                .controlSize(.small)
        }
    }
}

struct SubtitleInspectorPickerRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            content
        }
    }
}

struct SubtitleInspectorColorRow: View {
    let title: String
    @Binding var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(colorFromHex(value))
                    .frame(width: 32, height: 32)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12))
                    )

                TextField("#FFFFFF", text: $value)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 120)
                    .textSelection(.enabled)
            }
        }
    }
}

struct SubtitleInspectorNumberFieldRow: View {
    let title: String
    @Binding var value: Double
    let unit: String

    private var integerBinding: Binding<Int> {
        Binding(
            get: { Int(value.rounded()) },
            set: { value = Double($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField(title, value: integerBinding, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 88)

                Text(unit)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

func subtitleInspectorValue(_ value: Double, unit: String) -> String {
    let rounded = (value * 10).rounded() / 10
    let text: String

    if rounded == rounded.rounded() {
        text = "\(Int(rounded))"
    } else {
        text = rounded.formatted(.number.precision(.fractionLength(1)))
    }

    return "\(text) \(unit)"
}
