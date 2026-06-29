import SwiftUI

struct SubtitlePreviewCanvas: View {
    let style: SubtitleStyle

    private struct OutlineOffset {
        let id: Int
        let size: CGSize
    }

    private let previewText = "这是一条用于测试样式的字幕预览文本"

    private let outlineOffsets: [OutlineOffset] = [
        OutlineOffset(id: 0, size: CGSize(width: -1, height: 0)),
        OutlineOffset(id: 1, size: CGSize(width: 1, height: 0)),
        OutlineOffset(id: 2, size: CGSize(width: 0, height: -1)),
        OutlineOffset(id: 3, size: CGSize(width: 0, height: 1))
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.92),
                                Color(red: 0.12, green: 0.14, blue: 0.18),
                                Color(red: 0.18, green: 0.20, blue: 0.24)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08))

                VStack {
                    if style.position == .bottom {
                        Spacer()
                    } else if style.position == .middle {
                        Spacer()
                    }

                    subtitleText
                        .padding(.horizontal, 44)

                    if style.position == .top {
                        Spacer()
                    } else if style.position == .middle {
                        Spacer()
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)

                VStack {
                    HStack {
                        SettingsPill(text: "预览")
                        Spacer()
                    }
                    Spacer()
                }
                .padding(18)
            }
        }
        .frame(height: 280)
    }

    private var subtitleText: some View {
        ZStack {
            ForEach(outlineOffsets, id: \.id) { offset in
                Text(previewText)
                    .font(.custom(style.fontFamily, size: style.fontSize))
                    .fontWeight(subtitleFontWeight(style.fontWeight))
                    .foregroundStyle(colorFromHex(style.outlineColorHex))
                    .offset(
                        x: offset.size.width * style.outlineWidth,
                        y: offset.size.height * style.outlineWidth
                    )
            }

            Text(previewText)
                .font(.custom(style.fontFamily, size: style.fontSize))
                .fontWeight(subtitleFontWeight(style.fontWeight))
                .multilineTextAlignment(.center)
                .foregroundStyle(colorFromHex(style.fontColorHex))
                .shadow(
                    color: style.shadowEnabled ? Color.black.opacity(style.shadowOpacity) : .clear,
                    radius: 10,
                    x: 0,
                    y: 4
                )
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
