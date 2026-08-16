import AVFoundation
import Foundation
import Speech

protocol TranscriptionProvider {
    func transcribe(audioURL: URL, language: String) async throws -> [SubtitleSegment]
}

struct TranscriptionTestResult {
    let available: Bool
    let message: String
    let recognizedText: String?
}

final class AppleSpeechProvider: TranscriptionProvider {
    private let segmentationConfiguration: SubtitleSegmentationConfiguration

    init(segmentationConfiguration: SubtitleSegmentationConfiguration) {
        self.segmentationConfiguration = segmentationConfiguration
    }

    func transcribe(audioURL: URL, language: String) async throws -> [SubtitleSegment] {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard status == .authorized else {
            throw TranscriptionError.notAuthorized(status)
        }

        let locale = Locale(identifier: language)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable(language)
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.requiresOnDeviceRecognition = false
        request.addsPunctuation = true
        request.taskHint = .dictation

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            var latestSegments: [SubtitleSegment] = []

            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    guard !hasResumed else { return }
                    hasResumed = true
                    if latestSegments.isEmpty {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: latestSegments)
                    }
                    return
                }

                guard let result else { return }
                let appleSegments = result.bestTranscription.segments
                let timedWords = appleSegments.enumerated().map { index, segment in
                    let nextStart = appleSegments.indices.contains(index + 1)
                        ? appleSegments[index + 1].timestamp
                        : segment.timestamp + segment.duration
                    let end = Self.normalizedSegmentEnd(
                        start: segment.timestamp,
                        duration: segment.duration,
                        characterCount: segment.substring.count,
                        nextStart: nextStart
                    )
                    if segment.duration > 5.2 {
                        AppLog.transcription.warning(
                            "appleSpeech abnormalSegmentDuration raw=\(segment.duration, privacy: .public) clamped=\(end - segment.timestamp, privacy: .public) characterCount=\(segment.substring.count, privacy: .public)"
                        )
                    }
                    return SubtitleWord(
                        start: segment.timestamp,
                        end: max(end, segment.timestamp + 0.1),
                        text: segment.substring
                    )
                }
                latestSegments = TimedSubtitleSegmenter.segment(
                    timedWords,
                    configuration: self.segmentationConfiguration
                )

                if result.isFinal && !hasResumed {
                    let rawStart = timedWords.first?.start ?? 0
                    let rawEnd = timedWords.last?.end ?? 0
                    let outputStart = latestSegments.first?.start ?? 0
                    let outputEnd = latestSegments.last?.end ?? 0
                    AppLog.transcription.info(
                        "appleSpeech final rawSegments=\(timedWords.count, privacy: .public) rawRange=\(rawStart, privacy: .public)-\(rawEnd, privacy: .public) outputSegments=\(latestSegments.count, privacy: .public) outputRange=\(outputStart, privacy: .public)-\(outputEnd, privacy: .public) maxCharacters=\(self.segmentationConfiguration.maxCharacters, privacy: .public)"
                    )
                    hasResumed = true
                    continuation.resume(returning: latestSegments)
                }
            }

            Task {
                try? await Task.sleep(nanoseconds: 300_000_000_000)
                guard !hasResumed else { return }
                hasResumed = true
                task.cancel()
                if latestSegments.isEmpty {
                    continuation.resume(throwing: TranscriptionError.timeout)
                } else {
                    continuation.resume(returning: latestSegments)
                }
            }
        }
    }

    static func normalizedSegmentEnd(
        start: TimeInterval,
        duration: TimeInterval,
        characterCount: Int,
        nextStart: TimeInterval
    ) -> TimeInterval {
        let rawEnd = start + duration
        if duration > 5.2 {
            let readableDuration = max(1.2, min(3.0, Double(characterCount) * 0.45 + 0.6))
            return max(start + 0.1, min(min(rawEnd, start + readableDuration), nextStart))
        }
        return max(start + 0.1, min(rawEnd, max(nextStart, start + 0.1)))
    }

}
