import SwiftUI

struct WorkbenchHeaderActionButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  let isProminent: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 12, weight: .regular))
      .foregroundStyle(isProminent ? Color.white : Color.primary)
      .padding(.horizontal, 14)
      .frame(height: 34)
      .background(backgroundColor(isPressed: configuration.isPressed))
      .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
      .overlay {
        if !isProminent {
          RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        }
      }
      .opacity(isEnabled ? 1 : 0.5)
  }

  private func backgroundColor(isPressed: Bool) -> Color {
    if isProminent {
      return Color.accentColor.opacity(isPressed ? 0.82 : 1)
    }
    return Color.primary.opacity(isPressed ? 0.12 : 0.07)
  }
}
