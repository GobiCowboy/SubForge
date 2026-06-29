import SwiftUI

struct SubtitlePreviewCanvas: View {
    let style: SubtitleStyle

    private struct OutlineOffset: Identifiable {
        let id: Int
        let size: CGSize
    }

    private let previewText = "这是第一行字幕预览\n用于模拟真实落版效果"

    private var outlineOffsets: [OutlineOffset] {
        let distance = max(style.outlineWidth, 0.5)
        let baseOffsets = [
            CGSize(width: -distance, height: 0),
            CGSize(width: distance, height: 0),
            CGSize(width: 0, height: -distance),
            CGSize(width: 0, height: distance),
            CGSize(width: -distance, height: -distance),
            CGSize(width: distance, height: -distance),
            CGSize(width: -distance, height: distance),
            CGSize(width: distance, height: distance)
        ]

        return baseOffsets.enumerated().map { index, offset in
            OutlineOffset(id: index, size: offset)
        }
    }

    private var previewShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                previewShape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.08, green: 0.09, blue: 0.12),
                                Color(red: 0.12, green: 0.13, blue: 0.17),
                                Color(red: 0.17, green: 0.19, blue: 0.24)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                previewShape
                    .overlay(alignment: .topLeading) {
                        Circle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 180, height: 180)
                            .blur(radius: 50)
                            .offset(x: -40, y: -60)
                    }

                previewShape
                    .strokeBorder(Color.white.opacity(0.08))

                previewFrame(proxy: proxy)

                VStack {
                    HStack {
                        SettingsPill(text: "预览")
                        Spacer()
                    }
                    Spacer()
                }
                .padding(18)
            }
            .clipShape(previewShape)
        }
        .frame(height: 320)
    }

    @ViewBuilder
    private func previewFrame(proxy: GeometryProxy) -> some View {
        let horizontalPadding: CGFloat = 34
        let verticalPadding: CGFloat = 28
        let subtitleBlock = subtitleBlock(maxWidth: proxy.size.width - (horizontalPadding * 2))

        VStack {
            if style.position == .bottom || style.position == .middle {
                Spacer(minLength: 0)
            }

            if style.position == .middle {
                Spacer(minLength: 0)
            }

            subtitleBlock
                .frame(maxWidth: .infinity, alignment: previewAlignment)
                .offset(x: style.offsetX, y: style.offsetY)

            if style.position == .top || style.position == .middle {
                Spacer(minLength: 0)
            }

            if style.position == .top {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .frame(width: proxy.size.width, height: proxy.size.height)
    }

    private func subtitleBlock(maxWidth: CGFloat) -> some View {
        ZStack {
            if style.surfaceEnabled {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(colorFromHex(style.surfaceColorHex).opacity(style.surfaceOpacity))
                    .blur(radius: style.surfaceBlur)
            }

            subtitleText(maxWidth: maxWidth - 28)
                .padding(.horizontal, style.surfaceEnabled ? 14 : 0)
                .padding(.vertical, style.surfaceEnabled ? 10 : 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: maxWidth, alignment: previewAlignment)
    }

    private func subtitleText(maxWidth: CGFloat) -> some View {
        ZStack {
            if style.outlineEnabled {
                ForEach(outlineOffsets) { offset in
                    baseText(color: colorFromHex(style.outlineColorHex).opacity(style.outlineOpacity), maxWidth: maxWidth)
                        .offset(offset.size)
                        .blur(radius: style.outlineBlur)
                }
            }

            baseText(color: colorFromHex(style.fontColorHex), maxWidth: maxWidth)
        }
    }

    private func baseText(color: Color, maxWidth: CGFloat) -> some View {
        Text(previewText)
            .font(.custom(style.fontFamily, size: style.fontSize))
            .fontWeight(subtitleFontWeight(style.fontWeight))
            .tracking(style.characterSpacing)
            .lineSpacing(style.lineSpacing)
            .multilineTextAlignment(swiftUITextAlignment)
            .foregroundStyle(color)
            .frame(maxWidth: maxWidth, alignment: previewAlignment)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var previewAlignment: Alignment {
        switch style.horizontalAlignment {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }

    private var swiftUITextAlignment: TextAlignment {
        switch style.horizontalAlignment {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }
}

func subtitleFontWeight(_ weight: SubtitleFontWeight) -> Font.Weight {
    switch weight {
    case .regular: .regular
    case .medium: .medium
    case .semibold: .semibold
    case .bold: .bold
    }
}

func colorFromHex(_ hex: String) -> Color {
    let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: value).scanHexInt64(&int)

    let r, g, b: UInt64
    switch value.count {
    case 6:
        (r, g, b) = ((int >> 16) & 0xff, (int >> 8) & 0xff, int & 0xff)
    default:
        (r, g, b) = (255, 255, 255)
    }

    return Color(
        red: Double(r) / 255,
        green: Double(g) / 255,
        blue: Double(b) / 255
    )
}
