import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection: SettingsSection = .general
    @AppStorage("subforge.localTranscriptionEngine")
    private var storedLocalTranscriptionEngine = TranscriptionEngine.funASRLocal.rawValue

    private var settingsBinding: Binding<AppSettings> {
        Binding(
            get: { model.settings },
            set: { model.settings = $0 }
        )
    }

    private var selectedSubtitlePlan: SubtitlePlan {
        SubtitlePlan(engine: model.settings.transcriptionEngine)
    }

    private var storedLocalEngine: TranscriptionEngine {
        guard let engine = TranscriptionEngine(rawValue: storedLocalTranscriptionEngine),
              SubtitlePlan.localEngines.contains(engine) else {
            return .funASRLocal
        }
        return engine
    }

    private var pageTitleDetail: String? {
        selection == .subtitles ? selectedSubtitlePlan.title : nil
    }

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(
                selection: $selection,
                selectedSubtitlePlan: selectedSubtitlePlan,
                onSelectSubtitlePlan: selectSubtitlePlan
            )
                .frame(width: 240)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    SettingsPageHeader(title: selection.rawValue, detail: pageTitleDetail)

                    switch selection {
                    case .general:
                        GeneralSettingsPane(settings: settingsBinding)
                    case .subtitles:
                        SubtitleSettingsPane(settings: settingsBinding, service: model.smartService)
                    case .style:
                        SubtitleStyleSettingsPane(settings: settingsBinding)
                    case .export:
                        ExportSettingsPane(settings: settingsBinding)
                    case .watch:
                        WatchSettingsPane(settings: settingsBinding)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
                .frame(width: 632, alignment: .leading)
            }
            .frame(width: 659, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: rememberLocalEngineIfNeeded)
        .onChange(of: model.settings.transcriptionEngine) { _, engine in
            guard SubtitlePlan.localEngines.contains(engine) else { return }
            storedLocalTranscriptionEngine = engine.rawValue
        }
    }

    private func selectSubtitlePlan(_ plan: SubtitlePlan) {
        rememberLocalEngineIfNeeded()
        selection = .subtitles

        switch plan {
        case .official:
            model.settings.transcriptionEngine = .officialSmart
        case .custom:
            model.settings.transcriptionEngine = .cloudASR
        case .local:
            model.settings.transcriptionEngine = storedLocalEngine
        }
    }

    private func rememberLocalEngineIfNeeded() {
        let engine = model.settings.transcriptionEngine
        guard SubtitlePlan.localEngines.contains(engine) else { return }
        storedLocalTranscriptionEngine = engine.rawValue
    }
}
