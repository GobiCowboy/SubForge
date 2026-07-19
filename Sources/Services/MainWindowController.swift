import AppKit

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()

    private weak var window: NSWindow?
    private var hidesDockOnClose = true

    private override init() {
        super.init()
    }

    func attach(_ window: NSWindow) {
        self.window = window
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.title = "SubForge"
        // SwiftUI may replace the NSWindow delegate. Routing the close button
        // directly through this controller keeps the red button as “hide
        // window” instead of letting the last-window termination path run.
        if let closeButton = window.standardWindowButton(.closeButton) {
            closeButton.target = self
            closeButton.action = #selector(closeButtonPressed(_:))
        }
        AppLog.lifecycle.info("main window attached id=\(ObjectIdentifier(window).hashValue, privacy: .public)")
    }

    func showWindow() -> Bool {
        guard let window else {
            AppLog.lifecycle.warning("main window show failed, no attached window")
            return false
        }

        SubForgeAppDelegate.showDockIcon()

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        AppLog.lifecycle.info("main window shown id=\(ObjectIdentifier(window).hashValue, privacy: .public) visible=\(window.isVisible, privacy: .public)")
        return true
    }

    func setHidesDockOnClose(_ hidesDockOnClose: Bool) {
        self.hidesDockOnClose = hidesDockOnClose
    }

    @objc private func closeButtonPressed(_ sender: Any?) {
        guard let window else { return }
        window.orderOut(nil)
        if hidesDockOnClose {
            SubForgeAppDelegate.hideDockIconForMenuBarResidentMode()
        }
        AppLog.lifecycle.info("main window close button intercepted, hidden to menu bar")
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        if hidesDockOnClose {
            SubForgeAppDelegate.hideDockIconForMenuBarResidentMode()
        }
        AppLog.lifecycle.info("main window close intercepted, hidden to menu bar instead")
        return false
    }
}
