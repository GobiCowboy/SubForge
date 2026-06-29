import SwiftUI

struct WaveformTimelineView: View {
    let progress: Double
    let samples: [Double]
    let onScrub: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            let clampedProgress = min(max(progress, 0), 1)
            let playheadX = 18 + max(proxy.size.width - 36, 1) * clampedProgress

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))

                Canvas { context, size in
                    drawWaveform(in: &context, size: size, progress: clampedProgress)
                }

                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 1.5)
                    .overlay(alignment: .top) {
                        DownwardTriangle()
                            .fill(Color.accentColor)
                            .frame(width: 12, height: 8)
                            .offset(y: -1)
                    }
                    .offset(x: min(max(18, playheadX), proxy.size.width - 18))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let ratio = min(max(value.location.x / max(proxy.size.width, 1), 0), 1)
                        onScrub(ratio)
                    }
            )
        }
    }

    private func drawWaveform(in context: inout GraphicsContext, size: CGSize, progress: Double) {
        let values = samples.isEmpty ? Array(repeating: 0.12, count: 120) : samples
        let drawableWidth = max(size.width - 36, 1)
        let baseline = size.height / 2
        let step = drawableWidth / CGFloat(max(values.count - 1, 1))
        let barWidth = max(1.5, min(4.5, step * 0.48))

        for (index, value) in values.enumerated() {
            let x = 18 + CGFloat(index) * step
            let normalized = max(0.06, min(value, 1))
            let height = max(12, (size.height - 20) * normalized)
            let rect = CGRect(
                x: x - barWidth / 2,
                y: baseline - height / 2,
                width: barWidth,
                height: height
            )

            let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
            let isActive = Double(index) / Double(max(values.count - 1, 1)) <= progress
            context.fill(path, with: .color(isActive ? .accentColor : Color.secondary.opacity(0.22)))
        }
    }
}

private struct DownwardTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
