import AppKit

final class SubForgeAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        Self.showDockIcon()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        _ = MainWindowController.shared.showWindow()
        return false
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
