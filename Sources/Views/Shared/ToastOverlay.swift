import SwiftUI

struct ToastOverlay: View {
    let toast: ToastMessage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
            Text(toast.text)
                .lineLimit(2)
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(backgroundColor, in: Capsule())
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.15), radius: 12, y: 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var iconName: String {
        switch toast.level {
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    private var backgroundColor: Color {
        switch toast.level {
        case .info: .blue
        case .success: .green
        case .error: .red
        }
    }
}
