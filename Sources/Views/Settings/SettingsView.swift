import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection: SettingsSection = .general

    private var settingsBinding: Binding<AppSettings> {
        Binding(
            get: { model.settings },
            set: { model.settings = $0 }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $selection)
                .frame(width: 232)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    switch selection {
                    case .general:
                        GeneralSettingsPane(settings: settingsBinding)
                    case .transcription:
                        TranscriptionSettingsPane(settings: settingsBinding)
                    case .proofreading:
                        ProofreadingSettingsPane(settings: settingsBinding)
                    case .subtitle:
                        SubtitleStyleSettingsPane(settings: settingsBinding)
                    case .export:
                        ExportSettingsPane(settings: settingsBinding)
                    case .watch:
                        WatchSettingsPane(settings: settingsBinding)
                    }
                }
                .padding(.horizontal, 34)
                .padding(.vertical, 30)
                .frame(maxWidth: 940, alignment: .leading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .background(SettingsWindowChromeConfigurator())
    }
}
