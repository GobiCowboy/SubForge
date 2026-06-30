import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ZStack(alignment: .top) {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            HStack(spacing: 0) {
                ProjectSidebar(
                    onImport: { model.openImportPanel() },
                    onOpenSettings: { openSettings() }
                )

                Group {
                    switch model.mode {
                    case .home:
                        HomeView()
                    case .progress:
                        PipelineProgressView(onCancel: { model.resetWorkspace() })
                    case .editor:
                        WorkbenchView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let toast = model.toast {
                ToastOverlay(toast: toast)
                    .padding(.top, 20)
            }
        }
        .sheet(isPresented: $model.isShortcutGuidePresented) {
            ShortcutGuideSheet()
                .environmentObject(model)
        }
        .background(MainWindowCloseBehavior().frame(width: 0, height: 0))
    }
}
