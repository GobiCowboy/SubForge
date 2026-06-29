import AppKit
import Foundation

final class EditorKeyboardMonitor {
    private var keyDownMonitor: Any?

    func start(handler: @escaping (NSEvent) -> Bool) {
        guard keyDownMonitor == nil else { return }

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handler(event) ? nil : event
        }
    }

    func stop() {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
        }
        keyDownMonitor = nil
    }

    deinit {
        stop()
    }
}
