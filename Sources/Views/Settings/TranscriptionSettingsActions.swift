import SwiftUI

extension TranscriptionSettingsPane {
    func runTranscriptionTest() {
        let validationEngine = settings.transcriptionEngine
        guard let audioURL = SettingsTestAsset.audioURL() else {
            persistValidationState(
                SettingsValidationState(
                    hasValidated: true,
                    passed: false,
                    resultText: "没有找到测试音频，请确认应用已打包测试资源。"
                ),
                for: validationEngine
            )
            return
        }

        validationTask?.cancel()
        Task { await FunASRCLIRunner.shared.cancelActive() }

        isTesting = true

        validationTask = Task {
            var testSettings = settings
            SettingsStore.hydrateSecrets(into: &testSettings, includeASR: true, includeLLM: false)
            let provider = TranscriptionService.createProvider(settings: testSettings)
            do {
                let segments = try await provider.transcribe(audioURL: audioURL, language: testSettings.language)
                try Task.checkCancellation()
                let result = segments.map(\.text).joined(separator: "\n")
                await MainActor.run {
                    let state = SettingsValidationState(
                        hasValidated: true,
                        passed: !result.isEmpty,
                        resultText: result.isEmpty ? "识别完成，但没有得到可用文本。" : result
                    )
                    persistValidationState(state, for: validationEngine)
                    isTesting = false
                }
            } catch is CancellationError {
                await MainActor.run {
                    isTesting = false
                }
            } catch {
                guard !Task.isCancelled else {
                    await MainActor.run {
                        isTesting = false
                    }
                    return
                }
                await MainActor.run {
                    let state = SettingsValidationState(
                        hasValidated: true,
                        passed: false,
                        resultText: error.localizedDescription
                    )
                    persistValidationState(state, for: validationEngine)
                    isTesting = false
                }
            }
        }
    }

    func cancelValidation() {
        validationTask?.cancel()
        validationTask = nil
        isTesting = false
    }

    func hydrateCloudASRKeyIfNeeded() {
        guard settings.transcriptionEngine == .cloudASR else { return }
        var hydratedSettings = settings
        SettingsStore.hydrateSecrets(into: &hydratedSettings, includeASR: true, includeLLM: false)
        if hydratedSettings.cloudASRKey != settings.cloudASRKey {
            settings.hydrateCustomASRKey(hydratedSettings.cloudASRKey)
        }
    }

    func persistValidationState(
        _ state: SettingsValidationState,
        for engine: TranscriptionEngine? = nil
    ) {
        switch validationScope {
        case .custom:
            settings.customTranscriptionValidationState = state
        case .local:
            settings.localTranscriptionValidationState = state
        }
    }

    func clearActiveValidationIfNeeded() {
        switch validationScope {
        case .custom:
            settings.customTranscriptionValidationState = SettingsValidationState()
        case .local:
            settings.localTranscriptionValidationState = SettingsValidationState()
        }
    }

    func downloadModel(_ candidate: WhisperModel) {
        downloadingModel = candidate
        downloadProgress = 0

        Task {
            do {
                try await WhisperModelDownloader.download(candidate) { progress in
                    Task { @MainActor in
                        if downloadingModel == candidate {
                            downloadProgress = progress
                        }
                    }
                }
                await MainActor.run {
                    settings.setLocalWhisperModel(candidate)
                    downloadingModel = nil
                    downloadProgress = nil
                    model.toast = ToastMessage(text: "\(candidate.displayName) 下载完成", level: .success)
                }
            } catch {
                await MainActor.run {
                    downloadingModel = nil
                    downloadProgress = nil
                    model.toast = ToastMessage(text: error.localizedDescription, level: .error)
                }
            }
        }
    }

    func downloadFunASRModel() {
        isDownloadingFunASR = true
        funASRDownloadProgress = 0

        Task {
            do {
                try await FunASRModelDownloader.download(.sensevoiceSmallQ8) { progress in
                    Task { @MainActor in
                        if isDownloadingFunASR {
                            funASRDownloadProgress = progress
                        }
                    }
                }
                await MainActor.run {
                    isDownloadingFunASR = false
                    funASRDownloadProgress = nil
                    model.toast = ToastMessage(text: "SenseVoice + VAD 下载完成", level: .success)
                }
            } catch {
                await MainActor.run {
                    isDownloadingFunASR = false
                    funASRDownloadProgress = nil
                    model.toast = ToastMessage(text: error.localizedDescription, level: .error)
                }
            }
        }
    }

    var downloadProgressText: String {
        guard let downloadProgress else {
            return "下载中..."
        }
        return "下载中 \(Int(downloadProgress * 100))%"
    }

    var funASRDownloadProgressText: String {
        guard let funASRDownloadProgress else {
            return "下载中..."
        }
        return "下载中 \(Int(funASRDownloadProgress * 100))%"
    }
}
