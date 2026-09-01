import SwiftUI

struct KeyboardShortcutBadge: View {
  let text: String
  var compact = false
  var fontSize: CGFloat? = nil
  var fontWeight: Font.Weight = .semibold
  var height: CGFloat? = nil

  var body: some View {
    Text(text)
      .font(.system(size: fontSize ?? (compact ? 11 : 12), weight: fontWeight, design: .monospaced))
      .foregroundStyle(compact ? Color.secondary : Color.primary)
      .lineLimit(1)
      .padding(.horizontal, compact ? 7 : 8)
      .frame(height: height ?? (compact ? 22 : 24))
      .background(
        Color(nsColor: .controlBackgroundColor),
        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .strokeBorder(Color(nsColor: .separatorColor).opacity(0.28), lineWidth: 1)
      )
  }
}
