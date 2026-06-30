import AppKit

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()

    private weak var window: NSWindow?

    private override init() {
        super.init()
    }

    func attach(_ window: NSWindow) {
        self.window = window
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.title = "SubForge"
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        AppLog.lifecycle.info("main window attached id=\(ObjectIdentifier(window).hashValue, privacy: .public)")
    }

    func showWindow() -> Bool {
        guard let window else {
            AppLog.lifecycle.warning("main window show failed, no attached window")
            return false
        }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        AppLog.lifecycle.info("main window shown id=\(ObjectIdentifier(window).hashValue, privacy: .public) visible=\(window.isVisible, privacy: .public)")
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        AppLog.lifecycle.info("main window close intercepted, hidden instead")
        return false
    }

    func windowWillMiniaturize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        window.deminiaturize(nil)
        window.orderOut(nil)
        AppLog.lifecycle.info("main window miniaturize intercepted, hidden instead")
    }
}
