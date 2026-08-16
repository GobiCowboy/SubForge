import Foundation
import NaturalLanguage

extension TimedSubtitleSegmenter {
    static func semanticWords(
        _ input: [SubtitleWord],
        configuration: SubtitleSegmentationConfiguration,
        expandCoarseTokens: Bool
    ) -> [SubtitleWord] {
        let expanded: [TaggedWord]
        if expandCoarseTokens {
            expanded = input.flatMap { source -> [TaggedWord] in
                let pieces = lexicalPieces(source.text)
                guard !pieces.isEmpty else { return [] }
                let totalUnits = max(pieces.reduce(0) { $0 + max($1.text.count, 1) }, 1)
                let duration = max(source.end - source.start, 0.01)
                var cursor = source.start
                return pieces.enumerated().map { index, piece in
                    let weight = Double(max(piece.text.count, 1)) / Double(totalUnits)
                    let end = index == pieces.count - 1
                        ? source.end
                        : min(source.end, cursor + duration * weight)
                    let tagged = TaggedWord(
                        word: SubtitleWord(start: cursor, end: max(end, cursor + 0.005), text: piece.text),
                        lexicalClass: piece.lexicalClass
                    )
                    cursor = end
                    return tagged
                }
            }
        } else {
            expanded = input.map { source in
                let pieces = lexicalPieces(source.text)
                return TaggedWord(
                    word: source,
                    lexicalClass: pieces.count == 1 ? pieces[0].lexicalClass : nil
                )
            }
        }

        var merged: [TaggedWord] = []
        let phraseLimit = configuration.maxCharacters + max(2, configuration.maxCharacters / 8)
        for item in expanded {
            guard var previous = merged.last,
                  ((previous.lexicalClass == .noun && item.lexicalClass == .noun)
                    || (isTitlecaseLatinPhrase(previous.word.text) && isTitlecaseLatinPhrase(item.word.text))),
                  item.word.start - previous.word.end <= 0.45 else {
                merged.append(item)
                continue
            }
            let combined = joinedText([previous.word, item.word])
            guard combined.count <= phraseLimit else {
                merged.append(item)
                continue
            }
            previous.word.end = item.word.end
            previous.word.text = combined
            merged[merged.count - 1] = previous
        }
        return merged.map(\.word)
    }

    static func isTitlecaseLatinPhrase(_ text: String) -> Bool {
        let words = text.split(separator: " ")
        guard !words.isEmpty else { return false }
        return words.allSatisfy { word in
            guard let first = word.unicodeScalars.first, ("A"..."Z").contains(first) else { return false }
            return word.unicodeScalars.allSatisfy { $0.isTimedASCIIAlphaNumeric || $0 == "'" }
        }
    }

    static func lexicalPieces(_ text: String) -> [(text: String, lexicalClass: NLTag?)] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = trimmed
        let fullRange = trimmed.startIndex..<trimmed.endIndex
        let containsCJK = trimmed.unicodeScalars.contains { (0x3400...0x9FFF).contains(Int($0.value)) }
        tagger.setLanguage(containsCJK ? .simplifiedChinese : .english, range: fullRange)

        var pieces: [(text: String, lexicalClass: NLTag?)] = []
        var cursor = trimmed.startIndex
        tagger.enumerateTags(
            in: fullRange,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { tag, range in
            appendGap(String(trimmed[cursor..<range.lowerBound]), to: &pieces)
            pieces.append((String(trimmed[range]), tag))
            cursor = range.upperBound
            return true
        }
        appendGap(String(trimmed[cursor..<trimmed.endIndex]), to: &pieces)
        return pieces
    }

    static func appendGap(
        _ gap: String,
        to pieces: inout [(text: String, lexicalClass: NLTag?)]
    ) {
        for character in gap where !character.isWhitespace {
            pieces.append((String(character), nil))
        }
    }

    static func joinedText(_ words: [SubtitleWord]) -> String {
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

    static func shouldInsertSpace(_ left: Character?, _ right: Character?) -> Bool {
        guard let leftScalar = left?.unicodeScalars.last,
              let rightScalar = right?.unicodeScalars.first else {
            return false
        }
        return leftScalar.isTimedASCIIAlphaNumeric && rightScalar.isTimedASCIIAlphaNumeric
    }

    static func removeOverlaps(_ segments: [SubtitleSegment]) -> [SubtitleSegment] {
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
}
