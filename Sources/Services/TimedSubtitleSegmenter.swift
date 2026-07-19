import Foundation
import NaturalLanguage

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
    private struct TaggedWord {
        var word: SubtitleWord
        var lexicalClass: NLTag?
    }

    private static let strongBreaks: Set<Character> = ["。", "！", "？", "!", "?", ".", ";", "；"]
    private static let softBreaks: Set<Character> = ["，", ",", "、", "：", ":", "—", "–"]
    private static let weakLineEndWords: Set<String> = [
        "的", "了", "着", "过", "呢", "吗", "吧", "啊", "呀", "和", "与", "或", "但", "而",
        "在", "把", "被", "让", "从", "向", "对", "为", "是", "有", "就", "都", "又", "还",
        "也", "很", "更", "最", "不", "没", "会", "能", "可", "要", "将", "你", "我", "他",
        "她", "它", "这", "那", "其"
    ]

    static func segment(
        _ input: [SubtitleWord],
        configuration: SubtitleSegmentationConfiguration
    ) -> [SubtitleSegment] {
        let normalizedInput = input
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.end > $0.start }
            .sorted { $0.start < $1.start }
        let words = semanticWords(normalizedInput, configuration: configuration)
        guard !words.isEmpty else { return [] }

        var results: [SubtitleSegment] = []
        var current: [SubtitleWord] = []

        func emitPrefix(_ count: Int) {
            let safeCount = min(max(count, 0), current.count)
            guard safeCount > 0 else { return }
            let prefix = Array(current.prefix(safeCount))
            guard let first = prefix.first, let last = prefix.last else { return }
            results.append(
                SubtitleSegment(
                    start: first.start,
                    end: max(last.end, first.start + 0.1),
                    text: joinedText(prefix),
                    words: prefix
                )
            )
            current.removeFirst(safeCount)
        }

        func flush() {
            emitPrefix(current.count)
        }

        for word in words {
            let pause = word.start - (current.last?.end ?? word.start)
            if !current.isEmpty && pause > 0.65 {
                flush()
            }

            while !current.isEmpty,
                  joinedText(current + [word]).count > configuration.maxCharacters {
                emitPrefix(preferredBreakIndex(in: current, upcoming: word, configuration: configuration))
            }

            if let first = current.first, word.end - first.start > configuration.maxDuration {
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
                || (softBreak && (text.count >= preferredLength || duration >= configuration.preferredDuration)) {
                flush()
            }
        }

        flush()
        return removeOverlaps(results)
    }

    static func segmentEstimated(
        _ input: [SubtitleSegment],
        configuration: SubtitleSegmentationConfiguration
    ) -> [SubtitleSegment] {
        let coarseWords = input.map { segment in
            SubtitleWord(start: segment.start, end: segment.end, text: segment.text)
        }
        return segment(coarseWords, configuration: configuration)
    }

    /// 最大字数是排版目标，不是字符刀。超过目标时在附近的自然词边界回退，
    /// 宁可让一个不可拆的专名略微超出，也不把词组或英文名称劈开。
    private static func preferredBreakIndex(
        in current: [SubtitleWord],
        upcoming: SubtitleWord,
        configuration: SubtitleSegmentationConfiguration
    ) -> Int {
        guard current.count > 1 else { return current.count }
        let target = configuration.maxCharacters
        let minimum = max(4, Int(Double(target) * 0.52))
        var bestIndex = current.count
        var bestScore = Int.min

        for index in 1...current.count {
            let prefix = Array(current.prefix(index))
            let length = joinedText(prefix).count
            guard length >= minimum, length <= target else { continue }
            let previous = prefix.last!
            let next = index < current.count ? current[index] : upcoming
            var score = -abs(target - length) * 4

            if let last = previous.text.last, strongBreaks.contains(last) {
                score += 1_000
            } else if let last = previous.text.last, softBreaks.contains(last) {
                score += 650
            }

            let pause = next.start - previous.end
            if pause >= 0.25 {
                score += min(Int(pause * 300), 240)
            }

            let previousText = previous.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if weakLineEndWords.contains(previousText) {
                score -= 220
            }
            if next.text.count == 1, weakLineEndWords.contains(next.text) {
                score += 18
            }

            if score > bestScore {
                bestScore = score
                bestIndex = index
            }
        }
        return bestIndex
    }

    private static func semanticWords(
        _ input: [SubtitleWord],
        configuration: SubtitleSegmentationConfiguration
    ) -> [SubtitleWord] {
        let expanded = input.flatMap { source -> [TaggedWord] in
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

    private static func isTitlecaseLatinPhrase(_ text: String) -> Bool {
        let words = text.split(separator: " ")
        guard !words.isEmpty else { return false }
        return words.allSatisfy { word in
            guard let first = word.unicodeScalars.first, ("A"..."Z").contains(first) else { return false }
            return word.unicodeScalars.allSatisfy { $0.isASCIIAlphaNumeric || $0 == "'" }
        }
    }

    private static func lexicalPieces(_ text: String) -> [(text: String, lexicalClass: NLTag?)] {
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

    private static func appendGap(
        _ gap: String,
        to pieces: inout [(text: String, lexicalClass: NLTag?)]
    ) {
        for character in gap where !character.isWhitespace {
            pieces.append((String(character), nil))
        }
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
}
