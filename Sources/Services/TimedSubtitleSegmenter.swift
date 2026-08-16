import Foundation
import NaturalLanguage

struct SubtitleSegmentationConfiguration: Equatable {
    var maxCharacters: Int

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

    static let weakLineEndWords: Set<String> = [
        "的", "了", "着", "过", "呢", "吗", "吧", "啊", "呀", "和", "与", "或", "但", "而",
        "在", "把", "被", "让", "从", "向", "对", "为", "是", "有", "就", "都", "又", "还",
        "也", "很", "更", "最", "不", "没", "会", "能", "可", "要", "将", "你", "我", "他",
        "她", "它", "这", "那", "其", "需要"
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
        return segmentWordsWithinSource(
            normalizedInput,
            configuration: configuration,
            expandCoarseTokens: expandCoarseTokens
        )
    }

    static func segmentEstimated(
        _ input: [SubtitleSegment],
        configuration: SubtitleSegmentationConfiguration
    ) -> [SubtitleSegment] {
        segmentSources(input, configuration: configuration)
    }

    /// 官方服务会校对句子文本，但时间戳仍来自 ASR 原词。先按真实词时间得到边界，
    /// 再把校对后的文本按相同语义比例放回这些边界，避免校对后退化为整句均匀估时。
}
