import AppKit

final class SubForgeAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        applyActivationPolicy(for: SettingsStore.load())
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        _ = MainWindowController.shared.showWindow()
        sender.activate(ignoringOtherApps: true)
        return false
    }

    static func applyActivationPolicy(for settings: AppSettings) {
        applyActivationPolicy(showMenuBarIcon: settings.showMenuBarIcon)
    }

    static func applyActivationPolicy(showMenuBarIcon: Bool) {
        NSApp.setActivationPolicy(showMenuBarIcon ? .accessory : .regular)
    }

    private func applyActivationPolicy(for settings: AppSettings) {
        Self.applyActivationPolicy(for: settings)
    }
}
