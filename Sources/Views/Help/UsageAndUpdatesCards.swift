import SwiftUI

struct HelpIntroCard: View {
    let title: String
    let bodyText: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(bodyText)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .leading) {
            Capsule()
                .fill(Color.accentColor)
                .frame(width: 3)
                .padding(.vertical, 14)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.16), lineWidth: 1)
        )
    }
}

struct HelpSectionCard: View {
    let section: VersionHelpSection

    var body: some View {
        let visualStyle = HelpSectionVisualStyle(rawValue: section.style)

        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                if let icon = section.icon, !icon.isEmpty {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(visualStyle.iconColor)
                }
                Text(section.title)
                    .font(.system(size: 15, weight: .semibold))
            }

            if let blocks = section.blocks, !blocks.isEmpty {
                HelpRichBlocks(blocks: blocks)
            } else {
                Text(section.body)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                if !section.bullets.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(section.bullets, id: \.self) { bullet in
                            HStack(alignment: .firstTextBaseline, spacing: 9) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.tint)
                                Text(bullet)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.primary.opacity(0.8))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.top, 3)
                }
            }
        }
        .padding(visualStyle == .feature ? 18 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(visualStyle.background, in: RoundedRectangle(cornerRadius: visualStyle == .feature ? 16 : 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: visualStyle == .feature ? 16 : 12, style: .continuous)
                .strokeBorder(
                    visualStyle == .feature ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.09),
                    lineWidth: 1
                )
        )
    }
}
