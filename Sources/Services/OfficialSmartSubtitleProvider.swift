import AVFoundation
import Foundation

final class OfficialSmartSubtitleProvider: TranscriptionProvider {
    private let segmentationConfiguration: SubtitleSegmentationConfiguration
    private let onProgress: (@Sendable (OfficialSmartProgressUpdate) -> Void)?

    init(
        segmentationConfiguration: SubtitleSegmentationConfiguration = .init(maxCharacters: 24),
        onProgress: (@Sendable (OfficialSmartProgressUpdate) -> Void)? = nil
    ) {
        self.segmentationConfiguration = segmentationConfiguration
        self.onProgress = onProgress
    }

    func transcribe(audioURL: URL, language: String) async throws -> [SubtitleSegment] {
        guard let key = KeychainStore.read(.officialServiceKey) else {
            throw OfficialSmartServiceError.keyMissing
        }
        let segments = try await OfficialSmartServiceClient(
            profile: OfficialServiceConfiguration.activeProfile,
            apiKey: key,
            onProgress: onProgress
        ).process(audioURL: audioURL, language: language)
        return Self.applySegmentation(segments, configuration: segmentationConfiguration)
    }

    static func applySegmentation(
        _ segments: [SubtitleSegment],
        configuration: SubtitleSegmentationConfiguration
    ) -> [SubtitleSegment] {
        TimedSubtitleSegmenter.segmentPreservingCorrectedText(
            segments,
            configuration: configuration
        )
    }
}
