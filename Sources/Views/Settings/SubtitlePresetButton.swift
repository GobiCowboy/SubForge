import SwiftUI

struct SubtitlePresetButton: View {
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
