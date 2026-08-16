import Foundation

extension AppModel {
    func requestHotwordsOrStart(for url: URL) {
        switch settings.effectiveHotwordPromptPreference {
        case .undecided:
            hotwordPromptRequest = HotwordPromptRequest(url: url, kind: .onboarding)
        case .enabled:
            hotwordPromptRequest = HotwordPromptRequest(url: url, kind: .entry)
        case .disabled:
            continueStartingTranscription(for: url, hotwords: [])
        }
    }

    func enableHotwordsForPendingTranscription(_ request: HotwordPromptRequest) {
        guard hotwordPromptRequest?.id == request.id else { return }
        settings.hotwordPromptPreference = .enabled
        hotwordPromptRequest = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.hotwordPromptRequest = HotwordPromptRequest(url: request.url, kind: .entry)
        }
    }

    func disableHotwordsAndContinue(_ request: HotwordPromptRequest) {
        guard hotwordPromptRequest?.id == request.id else { return }
        settings.hotwordPromptPreference = .disabled
        hotwordPromptRequest = nil
        continueStartingTranscription(for: request.url, hotwords: [])
    }

    func submitHotwords(_ input: String, for request: HotwordPromptRequest) {
        guard hotwordPromptRequest?.id == request.id else { return }
        let hotwords = HotwordInputParser.parse(input)
        hotwordPromptRequest = nil
        continueStartingTranscription(for: request.url, hotwords: hotwords)
    }

    func cancelHotwordPrompt(_ request: HotwordPromptRequest) {
        guard hotwordPromptRequest?.id == request.id else { return }
        hotwordPromptRequest = nil
    }

    private func continueStartingTranscription(for url: URL, hotwords: [String]) {
        let runOptions = TranscriptionRunOptions(settings: settings, hotwords: hotwords)
        if !runOptions.hotwords.isEmpty,
           settings.transcriptionEngine != .officialSmart,
           !settings.shouldRunProofreading {
            notifyUser(
                "当前方案未启用 AI 校对，本次热词不会生效。",
                level: .info,
                duration: 4
            )
        }

        Task { @MainActor in
            if let existing = self.pipelineTask {
                existing.cancel()
                self.pipelineTask = nil
                await FunASRCLIRunner.shared.cancelActive()
            }

            let engine = self.settings.transcriptionEngine
            if LocalEngineUsageHint.shouldPresent(for: engine) {
                let proceed = await LocalEngineUsageHint.presentIfNeeded(for: engine)
                guard proceed else { return }
            }
            self.beginTranscriptionPipeline(for: url, runOptions: runOptions)
        }
    }
}
