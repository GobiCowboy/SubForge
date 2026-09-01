import SwiftUI

struct KeyboardShortcutBadge: View {
    let text: String
    var compact = false

    var body: some View {
        Text(text)
            .font(.system(size: compact ? 11 : 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, compact ? 7 : 8)
            .frame(height: compact ? 22 : 24)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.28), lineWidth: 1)
            )
    }
}
