import AppKit
import SwiftUI

struct MenuBarIconView: View {
    var body: some View {
        Image(nsImage: MenuBarIconFactory.makeImage())
            .renderingMode(.template)
    }
}

enum MenuBarIconFactory {
    static func makeImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)

        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.black.setFill()

        let waveformBars: [(CGFloat, CGFloat, CGFloat)] = [
            (1.4, 6.3, 5.4),
            (4.0, 4.4, 9.2),
            (6.6, 2.5, 13.0),
            (9.2, 4.0, 10.0)
        ]

        for (x, y, height) in waveformBars {
            NSBezierPath(
                roundedRect: NSRect(x: x, y: y, width: 1.7, height: height),
                xRadius: 0.85,
                yRadius: 0.85
            ).fill()
        }

        let captionBlocks = [
            NSRect(x: 12.2, y: 9.8, width: 4.2, height: 1.8),
            NSRect(x: 11.2, y: 6.6, width: 5.2, height: 1.8),
            NSRect(x: 12.6, y: 3.4, width: 3.8, height: 1.8)
        ]

        for rect in captionBlocks {
            NSBezierPath(roundedRect: rect, xRadius: 0.9, yRadius: 0.9).fill()
        }

        image.isTemplate = true
        return image
    }
}
