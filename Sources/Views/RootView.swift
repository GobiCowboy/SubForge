import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var versionContentService: VersionContentService
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ZStack(alignment: .top) {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            HStack(spacing: 0) {
                ProjectSidebar(
                    onImport: { model.openImportPanel() },
                    onOpenSettings: { model.presentSettings() },
                    onOpenUsageAndUpdates: { model.presentUsageAndUpdates() }
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
        .sheet(item: $model.hotwordPromptRequest) { request in
            HotwordPromptSheet(
                request: request,
                onEnable: { model.enableHotwordsForPendingTranscription(request) },
                onDisable: { model.disableHotwordsAndContinue(request) },
                onSubmit: { model.submitHotwords($0, for: request) },
                onCancel: { model.cancelHotwordPrompt(request) }
            )
        }
        .sheet(item: $versionContentService.pendingUpdate) { notice in
            VersionUpdateNoticeView(
                notice: notice,
                onLater: { versionContentService.dismissPendingUpdate() },
                onOpen: {
                    versionContentService.dismissPendingUpdate()
                    model.presentUsageAndUpdates(section: .updates)
                    openWindow(id: "usage-and-updates")
                }
            )
        }
        .onAppear {
            model.settingsWindowPresenter = {
                openSettings()
            }
            model.usageAndUpdatesWindowPresenter = {
                openWindow(id: "usage-and-updates")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                versionContentService.start()
            }
        }
        .background(MainWindowCloseBehavior().frame(width: 0, height: 0))
    }
}
