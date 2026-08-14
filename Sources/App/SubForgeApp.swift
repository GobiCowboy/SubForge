import AppKit
import SwiftUI

@main
struct SubForgeApp: App {
    @NSApplicationDelegateAdaptor(SubForgeAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @Environment(\.openWindow) private var openWindow

    @SceneBuilder
    var body: some Scene {
        mainWindow
        settingsWindow
        usageAndUpdatesWindow
    }

    private var settingsWindow: some Scene {
        Settings {
            SettingsView()
                .environmentObject(model)
                .frame(width: 900, height: 760)
        }
    }

    private var usageAndUpdatesWindow: some Scene {
        Window("使用说明与更新", id: "usage-and-updates") {
            UsageAndUpdatesView()
                .environmentObject(model)
                .environmentObject(model.versionContentService)
        }
        .defaultSize(width: 900, height: 680)
        .windowResizability(.contentMinSize)
    }

    private var mainWindow: some Scene {
        // The app has one primary workspace. Keep the scene keyed so the
        // existing window-management behavior remains stable, while using a
        // WindowGroup to mount RootView automatically at app launch.
        WindowGroup("SubForge", id: "main") {
            RootView()
                .environmentObject(model)
                .environmentObject(model.versionContentService)
                .frame(minWidth: 1180, minHeight: 760)
        }
        .commands {
            CommandMenu("字幕") {
                Button("打开文件") {
                    model.requestImportFromMenu()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("导出") {
                    model.exportArtifacts()
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(model.segments.isEmpty)

                Divider()

                Button("返回首页") {
                    if model.mode == .progress {
                        model.resetWorkspace()
                    } else {
                        model.showHome()
                    }
                }
                .disabled(model.mode == .home)
            }

            CommandMenu("播放") {
                Button(model.isPlaying ? "暂停" : "播放") {
                    model.togglePlayback()
                }
                .disabled(model.mode != .editor)

                Button("后退 1 秒") {
                    model.skip(by: -1)
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command])
                .disabled(model.mode != .editor)

                Button("前进 1 秒") {
                    model.skip(by: 1)
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command])
                .disabled(model.mode != .editor)
            }

            CommandMenu("帮助") {
                Button("使用帮助") {
                    openUsageAndUpdates(.help)
                }

                Button("最新动态") {
                    openUsageAndUpdates(.news)
                }

                Button("检查更新") {
                    openUsageAndUpdates(.updates)
                }

                Divider()

                Button("快捷键说明") {
                    model.presentShortcutGuide()
                }
                .keyboardShortcut("/", modifiers: [.command, .shift])
            }
        }
    }

    private func openUsageAndUpdates(_ section: UsageAndUpdatesSection) {
        model.requestedUsageAndUpdatesSection = section
        if section == .updates {
            model.versionContentService.checkForUpdates()
        }
        openWindow(id: "usage-and-updates")
    }

}
