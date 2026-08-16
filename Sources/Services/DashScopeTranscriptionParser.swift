import Foundation

struct DashScopeTranscriptionPayload {
    let words: [SubtitleWord]
    let sentences: [SubtitleSegment]
    let text: String
}

enum DashScopeTranscriptionParser {
    static func parse(_ data: Data) throws -> DashScopeTranscriptionPayload {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let transcripts = json["transcripts"] as? [[String: Any]] else {
            throw TranscriptionError.cloudResponseInvalid
        }

        var parsedWords: [SubtitleWord] = []
        var parsedSentences: [SubtitleSegment] = []
        var transcriptTexts: [String] = []

        for transcript in transcripts {
            if let text = cleanText(transcript["text"]) {
                transcriptTexts.append(text)
            }
            let sentences = transcript["sentences"] as? [[String: Any]] ?? []
            for sentence in sentences {
                var sentenceWords: [SubtitleWord] = []
                for word in sentence["words"] as? [[String: Any]] ?? [] {
                    guard let token = cleanText(word["text"]) else { continue }
                    let punctuation = cleanText(word["punctuation"]) ?? ""
                    let text = punctuation.isEmpty || token.hasSuffix(punctuation) ? token : token + punctuation
                    let start = milliseconds(word["begin_time"])
                    let end = max(milliseconds(word["end_time"]), start + 0.01)
                    let parsedWord = SubtitleWord(start: start, end: end, text: text)
                    sentenceWords.append(parsedWord)
                    parsedWords.append(parsedWord)
                }

                if let text = cleanText(sentence["text"]) ?? sentenceWordsText(sentenceWords) {
                    let start = sentenceWords.first?.start ?? milliseconds(sentence["begin_time"])
                    let end = sentenceWords.last?.end
                        ?? max(milliseconds(sentence["end_time"]), start + 0.1)
                    parsedSentences.append(
                        SubtitleSegment(
                            start: start,
                            end: max(end, start + 0.1),
                            text: text,
                            words: sentenceWords.isEmpty ? nil : sentenceWords
                        )
                    )
                }
            }
        }

        let fallbackText = parsedSentences.map(\.text).joined()
        return DashScopeTranscriptionPayload(
            words: parsedWords.sorted { $0.start < $1.start },
            sentences: parsedSentences.sorted { $0.start < $1.start },
            text: transcriptTexts.isEmpty ? fallbackText : transcriptTexts.joined(separator: "\n")
        )
    }

    private static func cleanText(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func milliseconds(_ value: Any?) -> TimeInterval {
        switch value {
        case let number as NSNumber:
            number.doubleValue / 1_000
        case let text as String:
            (Double(text) ?? 0) / 1_000
        default:
            0
        }
    }

    private static func sentenceWordsText(_ words: [SubtitleWord]) -> String? {
        let text = TimedSubtitleSegmenter.joinedText(words)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
