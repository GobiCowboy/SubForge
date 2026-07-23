import AVFoundation
import Foundation
import Speech

extension WhisperCppProvider {
    static func parseWhisperOutput(_ output: String) -> [SubtitleSegment] {
        output
            .components(separatedBy: .newlines)
            .compactMap(parseWhisperLine)
    }

    func alignLeadingSegmentStartIfNeeded(
        _ segments: [SubtitleSegment],
        offset: TimeInterval
    ) -> [SubtitleSegment] {
        guard offset > 0.4, let firstStart = segments.first?.start, firstStart < 0.5 else {
            return segments
        }

        AppLog.transcription.info(
            "whisperLeadingStartAligned offset=\(offset, privacy: .public) segmentCount=\(segments.count, privacy: .public)"
        )

        var aligned = segments
        let first = aligned[0]
        aligned[0] = SubtitleSegment(
            id: first.id,
            start: min(offset, max(first.start, first.end - 0.2)),
            end: first.end,
            text: first.text,
            words: nil
        )
        return aligned
    }

    static func parseWhisperLine(_ line: String) -> SubtitleSegment? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["),
              let closeBracket = trimmed.firstIndex(of: "]")
        else {
            return nil
        }

        let timeString = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closeBracket])
        let parts = timeString.components(separatedBy: "-->")
        guard parts.count == 2 else { return nil }

        let start = parseWhisperTime(parts[0].trimmingCharacters(in: .whitespaces))
        let end = parseWhisperTime(parts[1].trimmingCharacters(in: .whitespaces))
        let text = String(trimmed[trimmed.index(after: closeBracket)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        return SubtitleSegment(start: start, end: max(end, start + 0.1), text: text)
    }

    static func parseWhisperTime(_ string: String) -> TimeInterval {
        let parts = string.components(separatedBy: ":")
        guard parts.count == 3,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2])
        else {
            return 0
        }
        return hours * 3600 + minutes * 60 + seconds
    }
}
