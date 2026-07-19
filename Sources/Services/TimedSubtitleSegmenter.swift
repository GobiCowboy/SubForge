import Foundation

struct SubtitleSegmentationConfiguration: Equatable {
    var maxCharacters: Int
    var preferredDuration: TimeInterval = 3.6
    var maxDuration: TimeInterval = 5.2

    init(maxCharacters: Int) {
        self.maxCharacters = min(max(maxCharacters, 10), 50)
    }
}

private extension UnicodeScalar {
    var isASCIIAlphaNumeric: Bool {
        ("a"..."z").contains(self) || ("A"..."Z").contains(self) || ("0"..."9").contains(self)
    }
}

private extension Character {
    var isASCIIWordCharacter: Bool {
        unicodeScalars.allSatisfy { $0.isASCIIAlphaNumeric || $0 == "'" }
    }
}

enum TimedSubtitleSegmenter {
    private static let strongBreaks: Set<Character> = ["。", "！", "？", "!", "?", ".", ";", "；"]
    private static let softBreaks: Set<Character> = ["，", ",", "、", "：", ":", "—", "–"]

    static func segment(
        _ input: [SubtitleWord],
        configuration: SubtitleSegmentationConfiguration
    ) -> [SubtitleSegment] {
        let words = input
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.end > $0.start }
            .sorted { $0.start < $1.start }
        guard !words.isEmpty else { return [] }

        var results: [SubtitleSegment] = []
        var current: [SubtitleWord] = []

        func flush() {
            guard let first = current.first, let last = current.last else { return }
            results.append(
                SubtitleSegment(
                    start: first.start,
                    end: max(last.end, first.start + 0.1),
                    text: joinedText(current),
                    words: current
                )
            )
            current = []
        }

        for word in words {
            if shouldFlushBeforeAdding(word, to: current, configuration: configuration) {
                flush()
            }

            current.append(word)
            let text = joinedText(current)
            let duration = (current.last?.end ?? word.end) - (current.first?.start ?? word.start)
            let lastCharacter = text.last
            let strongBreak = lastCharacter.map { strongBreaks.contains($0) } ?? false
            let softBreak = lastCharacter.map { softBreaks.contains($0) } ?? false
            let preferredLength = max(8, Int(Double(configuration.maxCharacters) * 0.62))

            if strongBreak
                || duration >= configuration.maxDuration
                || text.count >= configuration.maxCharacters
                || (softBreak && (text.count >= preferredLength || duration >= configuration.preferredDuration)) {
                flush()
            }
        }

        flush()
        return enforceHardCharacterLimit(
            removeOverlaps(results),
            maxCharacters: configuration.maxCharacters
        )
    }

    static func segmentEstimated(
        _ input: [SubtitleSegment],
        configuration: SubtitleSegmentationConfiguration
    ) -> [SubtitleSegment] {
        let words = input.flatMap { segment -> [SubtitleWord] in
            let tokens = lexicalTokens(segment.text)
            guard !tokens.isEmpty else { return [] }

            let totalUnits = max(tokens.reduce(0) { $0 + max($1.count, 1) }, 1)
            let duration = max(segment.end - segment.start, 0.1)
            var cursor = segment.start

            return tokens.enumerated().map { index, token in
                let weight = Double(max(token.count, 1)) / Double(totalUnits)
                let end = index == tokens.count - 1
                    ? segment.end
                    : min(segment.end, cursor + duration * weight)
                let word = SubtitleWord(start: cursor, end: max(end, cursor + 0.01), text: token)
                cursor = end
                return word
            }
        }
        return segment(words, configuration: configuration)
    }

    private static func shouldFlushBeforeAdding(
        _ word: SubtitleWord,
        to current: [SubtitleWord],
        configuration: SubtitleSegmentationConfiguration
    ) -> Bool {
        guard let first = current.first else { return false }
        let proposedText = joinedText(current + [word])
        let proposedDuration = word.end - first.start
        return proposedText.count > configuration.maxCharacters
            || proposedDuration > configuration.maxDuration
            || word.start - (current.last?.end ?? word.start) > 0.65
    }

    private static func lexicalTokens(_ text: String) -> [String] {
        var tokens: [String] = []
        var latinWord = ""

        func flushLatinWord() {
            guard !latinWord.isEmpty else { return }
            tokens.append(latinWord)
            latinWord = ""
        }

        for character in text {
            if character.isASCIIWordCharacter {
                latinWord.append(character)
            } else {
                flushLatinWord()
                if !character.isWhitespace {
                    tokens.append(String(character))
                }
            }
        }
        flushLatinWord()
        return tokens
    }

    private static func joinedText(_ words: [SubtitleWord]) -> String {
        var result = ""
        for word in words {
            let text = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if shouldInsertSpace(result.last, text.first) {
                result.append(" ")
            }
            result.append(text)
        }
        return result
    }

    private static func shouldInsertSpace(_ left: Character?, _ right: Character?) -> Bool {
        guard let leftScalar = left?.unicodeScalars.last,
              let rightScalar = right?.unicodeScalars.first else {
            return false
        }
        return leftScalar.isASCIIAlphaNumeric && rightScalar.isASCIIAlphaNumeric
    }

    private static func removeOverlaps(_ segments: [SubtitleSegment]) -> [SubtitleSegment] {
        var normalized: [SubtitleSegment] = []
        for var segment in segments {
            if var previous = normalized.last, segment.start < previous.end {
                let lowerBound = previous.start + 0.1
                let upperBound = segment.end - 0.1
                if lowerBound < upperBound {
                    let boundary = min(max((previous.end + segment.start) / 2, lowerBound), upperBound)
                    previous.end = boundary
                    segment.start = boundary
                    normalized[normalized.count - 1] = previous
                }
            }
            guard segment.end > segment.start else { continue }
            normalized.append(segment)
        }
        return normalized
    }

    /// Sentence heuristics prefer word boundaries, but the user-facing maximum
    /// is an invariant. A single oversized Latin token or service result must
    /// still be split instead of escaping the configured limit.
    private static func enforceHardCharacterLimit(
        _ segments: [SubtitleSegment],
        maxCharacters: Int
    ) -> [SubtitleSegment] {
        segments.flatMap { segment in
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count > maxCharacters else { return [segment] }

            let characters = Array(text)
            let chunks = stride(from: 0, to: characters.count, by: maxCharacters).map { start in
                String(characters[start..<min(start + maxCharacters, characters.count)])
            }
            let duration = max(segment.end - segment.start, 0.1)
            let total = Double(characters.count)
            var consumed = 0

            return chunks.map { chunk in
                let start = segment.start + duration * Double(consumed) / total
                consumed += chunk.count
                let end = segment.start + duration * Double(consumed) / total
                return SubtitleSegment(start: start, end: max(end, start + 0.01), text: chunk)
            }
        }
    }
}
