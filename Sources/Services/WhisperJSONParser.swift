import Foundation

struct WhisperTranscriptionResult {
    var segments: [SubtitleSegment]
    var metalAvailable: Bool
    var dtwAligned: Bool
}

enum WhisperJSONParser {
    static func parse(_ data: Data) throws -> WhisperTranscriptionResult {
        let document = try JSONDecoder().decode(Document.self, from: data)
        var foundDTWTimestamp = false
        let segments = document.transcription.compactMap { item -> SubtitleSegment? in
            let parsedWords = parseWords(item.tokens, segmentEnd: milliseconds(item.offsets.to))
            let words = parsedWords.words
            foundDTWTimestamp = foundDTWTimestamp || parsedWords.usedDTW
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }

            let start = words.first?.start ?? milliseconds(item.offsets.from)
            let end = words.last?.end ?? milliseconds(item.offsets.to)
            return SubtitleSegment(
                start: start,
                end: max(end, start + 0.1),
                text: text,
                words: words.isEmpty ? nil : words
            )
        }

        return WhisperTranscriptionResult(
            segments: segments,
            metalAvailable: document.systeminfo.contains("MTL : EMBED_LIBRARY = 1"),
            dtwAligned: foundDTWTimestamp
        )
    }

    private static func parseWords(
        _ tokens: [Token],
        segmentEnd: TimeInterval
    ) -> (words: [SubtitleWord], usedDTW: Bool) {
        let textTokens = tokens.filter {
            !$0.text.hasPrefix("[") && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let usesDTW = textTokens.contains { ($0.tDTW ?? -1) >= 0 }

        let words = textTokens.enumerated().compactMap { index, token -> SubtitleWord? in
            let start = usesDTW
                ? centiseconds(token.tDTW ?? -1)
                : milliseconds(token.offsets.from)
            guard start >= 0 else { return nil }

            let nextDTWStart = textTokens.dropFirst(index + 1)
                .compactMap(\.tDTW)
                .first(where: { $0 >= 0 })
                .map(centiseconds)
            let end = usesDTW
                ? min(nextDTWStart ?? segmentEnd, segmentEnd)
                : milliseconds(token.offsets.to)
            guard end > start else { return nil }
            return SubtitleWord(start: start, end: end, text: token.text)
        }
        return (mergeEnglishTokenPieces(words), usesDTW)
    }

    private static func mergeEnglishTokenPieces(_ words: [SubtitleWord]) -> [SubtitleWord] {
        var merged: [SubtitleWord] = []
        for word in words {
            let normalized = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let continuesPreviousToken = word.text.first?.isWhitespace != true
                && normalized.isASCIIAlphaNumeric
                && merged.last?.text.trimmingCharacters(in: .whitespacesAndNewlines).isASCIIAlphaNumeric == true

            if continuesPreviousToken {
                merged[merged.count - 1].text += normalized
                merged[merged.count - 1].end = max(merged[merged.count - 1].end, word.end)
            } else {
                merged.append(word)
            }
        }
        return merged
    }

    private static func milliseconds(_ value: Int) -> TimeInterval {
        TimeInterval(value) / 1_000
    }

    private static func centiseconds(_ value: Int) -> TimeInterval {
        TimeInterval(value) / 100
    }
}

private struct Document: Decodable {
    var systeminfo: String
    var transcription: [Transcription]
}

private struct Transcription: Decodable {
    var offsets: Offsets
    var text: String
    var tokens: [Token]
}

private struct Token: Decodable {
    var text: String
    var offsets: Offsets
    var tDTW: Int?

    private enum CodingKeys: String, CodingKey {
        case text, offsets
        case tDTW = "t_dtw"
    }
}

private struct Offsets: Decodable {
    var from: Int
    var to: Int
}

private extension String {
    var isASCIIAlphaNumeric: Bool {
        !isEmpty && unicodeScalars.allSatisfy {
            ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0)
        }
    }
}
