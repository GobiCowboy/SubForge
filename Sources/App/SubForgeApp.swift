import SwiftUI

@main
struct SubForgeApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("SubForge") {
            RootView()
                .environmentObject(model)
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
                Button("快捷键说明") {
                    model.presentShortcutGuide()
                }
                .keyboardShortcut("/", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
                .frame(width: 900, height: 760)
        }
    }
}
