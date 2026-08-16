import SwiftUI
import UniformTypeIdentifiers

struct WatchStatusDot: View {
    let color: Color
    let isAnimated: Bool

    @State private var glow = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(isAnimated ? 0.18 : 0.12))
                .frame(width: 16, height: 16)
                .scaleEffect(isAnimated && glow ? 1.35 : 1.0)
                .opacity(isAnimated && glow ? 0.35 : 0.8)

            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
        .onAppear {
            guard isAnimated else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                glow = true
            }
        }
    }
}
