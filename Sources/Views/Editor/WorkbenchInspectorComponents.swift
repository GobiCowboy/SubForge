import SwiftUI

enum InspectorStyle {
  static let sectionTitle = Font.system(size: 16, weight: .semibold)

  static func secondaryFont(weight: Font.Weight = .regular) -> Font {
    .system(size: 12, weight: weight)
  }
}

struct InspectorSectionHeader: View {
  let title: String
  var trailing: String? = nil

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title)
        .font(InspectorStyle.sectionTitle)
      Spacer(minLength: 12)
      if let trailing {
        Text(trailing)
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(.secondary)
      }
    }
  }
}

struct InspectorDashedDivider: View {
  var body: some View {
    GeometryReader { geometry in
      Path { path in
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: geometry.size.width, y: 0))
      }
      .stroke(
        Color(nsColor: .separatorColor).opacity(0.45),
        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
      )
    }
    .frame(height: 1)
  }
}

struct InspectorActionRow: View {
  @Environment(\.isEnabled) private var isEnabled

  let title: String
  let icon: String
  let shortcut: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: icon)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.secondary)
          .frame(width: 28, height: 28)
          .background(
            Color.secondary.opacity(isEnabled ? 0.12 : 0.07),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
          )

        Text(title)
          .font(InspectorStyle.secondaryFont(weight: .medium))
          .foregroundStyle(isEnabled ? .primary : .secondary)

        Spacer(minLength: 8)

        KeyboardShortcutBadge(text: shortcut, compact: true, fontSize: 11)
          .opacity(isEnabled ? 1 : 0.55)
          .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
              .strokeBorder(Color.secondary.opacity(0.14), lineWidth: 1)
          )
      }
      .padding(.horizontal, 10)
      .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
      .background(
        Color(nsColor: .textBackgroundColor).opacity(isEnabled ? 0.52 : 0.25),
        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
      )
    }
    .buttonStyle(.plain)
    .help("\(title)（\(shortcut.replacingOccurrences(of: " ", with: ""))）")
  }
}
