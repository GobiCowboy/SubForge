import SwiftUI

@main
struct SubForgeApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 800, minHeight: 600)
        }
        .commands {
            CommandGroup(after: .saveItem) {
                Button("保存 SRT") {
                    appState.saveSRT()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!appState.canSave)
            }
        }
    }
}
