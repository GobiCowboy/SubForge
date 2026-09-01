import Foundation

enum SubtitleSplitError: LocalizedError, Equatable {
    case emptySide
    case invalidCaretPosition
    case playheadOutsideSegment
    case segmentTooShort

    var errorDescription: String? {
        switch self {
        case .emptySide:
            return "分割点不能放在字幕开头或结尾"
        case .invalidCaretPosition:
            return "请把文本光标放在两个字符之间"
        case .playheadOutsideSegment:
            return "播放头需要位于当前字幕的中间位置"
        case .segmentTooShort:
            return "当前字幕太短，无法安全分割"
        }
    }
}

struct SubtitleSplitResult: Equatable {
    let left: SubtitleSegment
    let right: SubtitleSegment
    let splitTime: TimeInterval
    let usesEstimatedTime: Bool
}

enum SubtitleSplitService {
    private static let minimumDuration: TimeInterval = 0.1

    static func splitAtCaret(
        _ segment: SubtitleSegment,
        utf16Offset: Int
    ) throws -> SubtitleSplitResult {
        let splitIndex = try stringIndex(in: segment.text, utf16Offset: utf16Offset)
        let leftText = String(segment.text[..<splitIndex])
        let rightText = String(segment.text[splitIndex...])
        guard !leftText.isEmpty, !rightText.isEmpty else {
            throw SubtitleSplitError.emptySide
        }

        let spans = wordSpans(in: segment)
        let timedSplit = timeForCaret(
            utf16Offset: utf16Offset,
            in: segment,
            spans: spans
        )
        return try makeResult(
            from: segment,
            leftText: leftText,
            rightText: rightText,
            splitUTF16Offset: utf16Offset,
            splitTime: timedSplit.time,
            usesEstimatedTime: timedSplit.estimated
        )
    }

    static func splitAtPlayhead(
        _ segment: SubtitleSegment,
        time: TimeInterval
    ) throws -> SubtitleSplitResult {
        guard segment.end - segment.start > minimumDuration * 2 else {
            throw SubtitleSplitError.segmentTooShort
        }
        guard time > segment.start + minimumDuration,
              time < segment.end - minimumDuration else {
            throw SubtitleSplitError.playheadOutsideSegment
        }

        let spans = wordSpans(in: segment)
        let utf16Offset = textOffsetNear(time: time, in: segment, spans: spans)
        let splitIndex = try stringIndex(in: segment.text, utf16Offset: utf16Offset)
        let leftText = String(segment.text[..<splitIndex])
        let rightText = String(segment.text[splitIndex...])
        guard !leftText.isEmpty, !rightText.isEmpty else {
            throw SubtitleSplitError.emptySide
        }

        return try makeResult(
            from: segment,
            leftText: leftText,
            rightText: rightText,
            splitUTF16Offset: splitIndex.utf16Offset(in: segment.text),
            splitTime: time,
            usesEstimatedTime: spans.isEmpty
        )
    }

    private struct WordSpan {
        let word: SubtitleWord
        let range: Range<String.Index>
    }

    private static func makeResult(
        from segment: SubtitleSegment,
        leftText: String,
        rightText: String,
        splitUTF16Offset: Int,
        splitTime: TimeInterval,
        usesEstimatedTime: Bool
    ) throws -> SubtitleSplitResult {
        guard segment.end - segment.start > minimumDuration * 2 else {
            throw SubtitleSplitError.segmentTooShort
        }
        let safeSplitTime = min(
            max(splitTime, segment.start + minimumDuration),
            segment.end - minimumDuration
        )
        guard safeSplitTime > segment.start,
              safeSplitTime < segment.end else {
            throw SubtitleSplitError.segmentTooShort
        }

        let spans = wordSpans(in: segment)
        let (leftWords, rightWords) = splitWords(
            spans,
            atUTF16Offset: splitUTF16Offset,
            in: segment.text
        )

        let left = SubtitleSegment(
            id: segment.id,
            start: segment.start,
            end: safeSplitTime,
            text: leftText,
            words: leftWords.isEmpty ? nil : leftWords
        )
        let right = SubtitleSegment(
            start: safeSplitTime,
            end: segment.end,
            text: rightText,
            words: rightWords.isEmpty ? nil : rightWords
        )
        return SubtitleSplitResult(
            left: left,
            right: right,
            splitTime: safeSplitTime,
            usesEstimatedTime: usesEstimatedTime
        )
    }

    private static func timeForCaret(
        utf16Offset: Int,
        in segment: SubtitleSegment,
        spans: [WordSpan]
    ) -> (time: TimeInterval, estimated: Bool) {
        if let span = spans.first(where: { $0.range.upperBound.utf16Offset(in: segment.text) == utf16Offset }) {
            return (span.word.end, false)
        }

        if let span = spans.first(where: {
            let start = $0.range.lowerBound.utf16Offset(in: segment.text)
            let end = $0.range.upperBound.utf16Offset(in: segment.text)
            return utf16Offset > start && utf16Offset < end
        }) {
            let start = span.range.lowerBound.utf16Offset(in: segment.text)
            let width = max(span.range.upperBound.utf16Offset(in: segment.text) - start, 1)
            let ratio = Double(utf16Offset - start) / Double(width)
            return (span.word.start + (span.word.end - span.word.start) * ratio, false)
        }

        return (proportionalTime(utf16Offset: utf16Offset, in: segment), true)
    }

    private static func textOffsetNear(
        time: TimeInterval,
        in segment: SubtitleSegment,
        spans: [WordSpan]
    ) -> Int {
        let boundaries = spans.dropLast().map {
            (offset: $0.range.upperBound.utf16Offset(in: segment.text), time: $0.word.end)
        }
        if let nearest = boundaries.min(by: { abs($0.time - time) < abs($1.time - time) }) {
            return nearest.offset
        }

        let ratio = (time - segment.start) / max(segment.end - segment.start, 0.1)
        let target = Int((Double(segment.text.utf16.count) * ratio).rounded())
        return nearestCharacterBoundary(in: segment.text, aroundUTF16Offset: target)
    }

    private static func proportionalTime(
        utf16Offset: Int,
        in segment: SubtitleSegment
    ) -> TimeInterval {
        let ratio = Double(utf16Offset) / Double(max(segment.text.utf16.count, 1))
        return segment.start + (segment.end - segment.start) * ratio
    }

    private static func splitWords(
        _ spans: [WordSpan],
        atUTF16Offset splitOffset: Int,
        in text: String
    ) -> (left: [SubtitleWord], right: [SubtitleWord]) {
        var left: [SubtitleWord] = []
        var right: [SubtitleWord] = []

        for span in spans {
            let start = span.range.lowerBound.utf16Offset(in: text)
            let end = span.range.upperBound.utf16Offset(in: text)
            if end <= splitOffset {
                left.append(span.word)
            } else if start >= splitOffset {
                right.append(span.word)
            } else {
                let relativeOffset = splitOffset - start
                let splitIndex = String.Index(utf16Offset: relativeOffset, in: String(text[span.range]))
                let wordText = String(text[span.range])
                let leftText = String(wordText[..<splitIndex])
                let rightText = String(wordText[splitIndex...])
                let ratio = Double(relativeOffset) / Double(max(wordText.utf16.count, 1))
                let middle = span.word.start + (span.word.end - span.word.start) * ratio
                if !leftText.isEmpty {
                    left.append(SubtitleWord(start: span.word.start, end: middle, text: leftText))
                }
                if !rightText.isEmpty {
                    right.append(SubtitleWord(start: middle, end: span.word.end, text: rightText))
                }
            }
        }

        return (left, right)
    }

    private static func wordSpans(in segment: SubtitleSegment) -> [WordSpan] {
        guard let words = segment.words, !words.isEmpty else { return [] }
        var searchStart = segment.text.startIndex
        return words.compactMap { word in
            let normalized = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty,
                  searchStart <= segment.text.endIndex,
                  let range = segment.text.range(of: normalized, range: searchStart..<segment.text.endIndex) else {
                return nil
            }
            searchStart = range.upperBound
            return WordSpan(word: word, range: range)
        }
    }

    private static func stringIndex(in text: String, utf16Offset: Int) throws -> String.Index {
        guard utf16Offset > 0, utf16Offset < text.utf16.count else {
            throw SubtitleSplitError.emptySide
        }
        let index = String.Index(utf16Offset: utf16Offset, in: text)
        guard index.utf16Offset(in: text) == utf16Offset else {
            throw SubtitleSplitError.invalidCaretPosition
        }
        return index
    }

    private static func nearestCharacterBoundary(in text: String, aroundUTF16Offset offset: Int) -> Int {
        let clamped = min(max(offset, 1), max(text.utf16.count - 1, 1))
        var best = 1
        var bestDistance = Int.max
        for index in text.indices {
            let current = index.utf16Offset(in: text)
            guard current > 0, current < text.utf16.count else { continue }
            let distance = abs(current - clamped)
            if distance < bestDistance {
                best = current
                bestDistance = distance
            }
        }
        return best
    }
}
