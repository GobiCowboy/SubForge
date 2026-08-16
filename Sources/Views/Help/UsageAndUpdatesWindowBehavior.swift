import AppKit
import SwiftUI

struct UsageAndUpdatesWindowBehavior: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowConfiguratorView {
        WindowConfiguratorView()
    }

    func updateNSView(_ nsView: WindowConfiguratorView, context: Context) {
        nsView.configureIfNeeded()
    }

    final class WindowConfiguratorView: NSView {
        private weak var configuredWindow: NSWindow?
        private var activationObserver: NSObjectProtocol?

        deinit {
            if let activationObserver {
                NotificationCenter.default.removeObserver(activationObserver)
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let activationObserver {
                NotificationCenter.default.removeObserver(activationObserver)
                self.activationObserver = nil
            }

            if let window {
                activationObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didBecomeKeyNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    self?.exitFullScreenIfNeeded()
                }
            }

            configureIfNeeded()
        }

        func configureIfNeeded() {
            guard let window, configuredWindow !== window else { return }
            configuredWindow = window

            window.title = "使用说明与更新"
            window.isRestorable = false
            window.minSize = NSSize(width: 820, height: 600)

            if window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    Self.applyDesktopFrame(to: window)
                }
            } else {
                Self.applyDesktopFrame(to: window)
            }
        }

        private func exitFullScreenIfNeeded() {
            guard let window, window.styleMask.contains(.fullScreen) else { return }
            window.toggleFullScreen(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                Self.applyDesktopFrame(to: window)
            }
        }

        private static func applyDesktopFrame(to window: NSWindow) {
            window.setContentSize(NSSize(width: 900, height: 680))
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
