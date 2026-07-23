import AVFoundation
import Foundation
import Speech

final class WhisperCppProvider: TranscriptionProvider {
    let model: WhisperModel
    let segmentationConfiguration: SubtitleSegmentationConfiguration

    init(model: WhisperModel, segmentationConfiguration: SubtitleSegmentationConfiguration) {
        self.model = model
        self.segmentationConfiguration = segmentationConfiguration
    }

    func transcribe(audioURL: URL, language: String) async throws -> [SubtitleSegment] {
        let cliPath = try resolveCLIPath()
        let modelPath = try resolveModelPath()
        let prepared = try SandboxMediaAccess.prepareForProcessing(audioURL)
        defer { prepared.cleanup() }

        let wavURL = FileManager.default.temporaryDirectory.appendingPathComponent("subforge_whisper_\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: wavURL) }

        try await Task.detached(priority: .userInitiated) {
            try Self.convertToWAV(input: prepared.url, output: wavURL)
        }.value

        let dtwPreset = model.rawValue

        let whisperResult = try await Task.detached(priority: .userInitiated) {
            try Self.runWhisperCLI(
                cliPath: cliPath,
                modelPath: modelPath,
                wavURL: wavURL,
                language: language,
                dtwPreset: dtwPreset
            )
        }.value

        let rawSegments = whisperResult.segments
        let timedWords = rawSegments.flatMap { $0.words ?? [] }
        let parsed = timedWords.isEmpty
            ? TimedSubtitleSegmenter.segmentEstimated(rawSegments, configuration: segmentationConfiguration)
            : TimedSubtitleSegmenter.segment(timedWords, configuration: segmentationConfiguration)
        guard !parsed.isEmpty else {
            throw TranscriptionError.emptyResult
        }
        return parsed
    }
}
