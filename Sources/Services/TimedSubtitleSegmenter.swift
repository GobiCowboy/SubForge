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

extension UnicodeScalar {
    var isTimedASCIIAlphaNumeric: Bool {
        ("a"..."z").contains(self) || ("A"..."Z").contains(self) || ("0"..."9").contains(self)
    }
}

extension Character {
    var isTimedASCIIWordCharacter: Bool {
        unicodeScalars.allSatisfy { $0.isTimedASCIIAlphaNumeric || $0 == "'" }
    }
}

enum TimedSubtitleSegmenter {
    struct TaggedWord {
        var word: SubtitleWord
        var lexicalClass: NLTag?
    }

    static let strongBreaks: Set<Character> = ["。", "！", "？", "!", "?", ".", ";", "；"]
    static let softBreaks: Set<Character> = ["，", ",", "、", "：", ":", "—", "–"]
    static let weakLineEndWords: Set<String> = [
        "的", "了", "着", "过", "呢", "吗", "吧", "啊", "呀", "和", "与", "或", "但", "而",
        "在", "把", "被", "让", "从", "向", "对", "为", "是", "有", "就", "都", "又", "还",
        "也", "很", "更", "最", "不", "没", "会", "能", "可", "要", "将", "你", "我", "他",
        "她", "它", "这", "那", "其"
    ]

    static func segment(
        _ input: [SubtitleWord],
        configuration: SubtitleSegmentationConfiguration
    ) -> [SubtitleSegment] {
        segment(input, configuration: configuration, expandCoarseTokens: false)
    }

    static func segment(
        _ input: [SubtitleWord],
        configuration: SubtitleSegmentationConfiguration,
        expandCoarseTokens: Bool
    ) -> [SubtitleSegment] {
        let normalizedInput = input
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.end > $0.start }
            .sorted { $0.start < $1.start }
        let words = semanticWords(
            normalizedInput,
            configuration: configuration,
            expandCoarseTokens: expandCoarseTokens
        )
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
        return segment(
            coarseWords,
            configuration: configuration,
            expandCoarseTokens: true
        )
    }

    /// 官方服务会校对句子文本，但时间戳仍来自 ASR 原词。先按真实词时间得到边界，
    /// 再把校对后的文本按相同语义比例放回这些边界，避免校对后退化为整句均匀估时。
}
