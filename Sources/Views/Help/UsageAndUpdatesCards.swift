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
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(section.title)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
            }

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
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.09))
                .frame(height: 1)
        }
    }
}
