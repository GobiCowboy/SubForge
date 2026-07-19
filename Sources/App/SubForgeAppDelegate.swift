import AppKit

final class SubForgeAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        Self.showDockIcon()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        _ = MainWindowController.shared.showWindow()
        return false
    }

    // Closing the workspace should leave the menu-bar app running. The user
    // can reopen it from “显示 SubForge” or the Applications menu.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    static func applyActivationPolicy(for settings: AppSettings) {
        showDockIcon()
    }

    static func showDockIcon() {
        NSApp.setActivationPolicy(.regular)
    }

    static func hideDockIconForMenuBarResidentMode() {
        NSApp.setActivationPolicy(.accessory)
    }

    private func applyActivationPolicy(for settings: AppSettings) {
        Self.applyActivationPolicy(for: settings)
    }
}
