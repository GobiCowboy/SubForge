import Foundation

enum SubtitleSegmentationService {
    private static let strongBreaks: Set<Character> = ["。", "！", "？", "!", "?", ";", "；"]
    private static let softBreaks: Set<Character> = ["，", ",", "：", ":", "—", "–"]
    private static let minChunkLength = 4
    private static let minSoftBreakLength = 8
    private static let preferredChunkLength = 24
    private static let hardChunkLength = 42
    private static let minDuration: TimeInterval = 0.9
    private static let preferredDuration: TimeInterval = 3.6
    private static let hardDuration: TimeInterval = 5.2
    private static let mergeGap: TimeInterval = 0.35
    private static let continuationDuration: TimeInterval = 12.0
    private static let continuationLength = 220

    static func refine(_ segments: [SubtitleSegment]) -> [SubtitleSegment] {
        let normalized = segments.compactMap(normalize)
        guard !normalized.isEmpty else { return [] }

        let continuationMerged = mergeContinuationSegments(normalized)
        let split = continuationMerged.flatMap(splitIfNeeded)
        let merged = mergeShortSegments(split)
        let reflowed = mergeContinuationSegments(merged)

        return reflowed
            .flatMap(splitIfNeeded)
            .compactMap(normalize)
    }

    private static func normalize(_ segment: SubtitleSegment) -> SubtitleSegment? {
        let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var normalized = segment
        normalized.text = trimmed
        normalized.end = max(normalized.end, normalized.start + 0.1)
        return normalized
    }

    private static func splitIfNeeded(_ segment: SubtitleSegment) -> [SubtitleSegment] {
        let duration = segment.end - segment.start
        let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { return [] }
        let shouldSplitAtPunctuation = text.count > preferredChunkLength && containsBreak(in: text)
        guard duration > hardDuration || text.count > hardChunkLength || shouldSplitAtPunctuation else {
            return [segment]
        }

        let parts = chunkText(text)
        guard parts.count > 1 else {
            return [segment]
        }

        let totalUnits = max(parts.reduce(0) { $0 + max($1.count, 1) }, 1)
        var cursor = segment.start
        var searchStart = segment.text.startIndex

        return parts.enumerated().map { index, part in
            let partRange = segment.text.range(of: part, range: searchStart..<segment.text.endIndex)
            let characterOffset = partRange.map { segment.text.distance(from: segment.text.startIndex, to: $0.lowerBound) }
            if let partRange {
                searchStart = partRange.upperBound
            }
            let matchedWords = words(in: segment, for: part, startingAt: characterOffset)
            if let first = matchedWords.first, let last = matchedWords.last {
                return SubtitleSegment(
                    start: first.start,
                    end: max(last.end, first.start + 0.1),
                    text: part,
                    words: matchedWords
                )
            }

            let weight = Double(max(part.count, 1)) / Double(totalUnits)
            let partDuration = index == parts.count - 1
                ? max(segment.end - cursor, 0.1)
                : max((segment.end - segment.start) * weight, 0.35)
            let start = cursor
            let end = min(segment.end, cursor + partDuration)
            cursor = end
            return SubtitleSegment(start: start, end: max(end, start + 0.1), text: part)
        }
    }

    private static func words(
        in segment: SubtitleSegment,
        for part: String,
        startingAt characterOffset: Int?
    ) -> [SubtitleWord] {
        guard let words = segment.words, !words.isEmpty, let characterOffset else { return [] }

        let partStart = characterOffset
        let partEnd = characterOffset + part.count
        var cursor = 0

        return words.filter { word in
            let normalized = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if cursor > 0, word.text.first?.isWhitespace == true {
                cursor += 1
            }
            let wordStart = cursor
            let wordEnd = cursor + normalized.count
            cursor = wordEnd
            return wordEnd > partStart && wordStart < partEnd
        }
    }

    private static func chunkText(_ text: String) -> [String] {
        var rawParts: [String] = []
        var current = ""

        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                rawParts.append(trimmed)
            }
            current = ""
        }

        for character in text {
            current.append(character)

            if strongBreaks.contains(character), current.count >= minChunkLength {
                flush()
                continue
            }

            if softBreaks.contains(character), current.count >= minSoftBreakLength {
                flush()
                continue
            }

            if current.count >= preferredChunkLength,
               current.last.map({ strongBreaks.contains($0) || softBreaks.contains($0) }) == true {
                flush()
                continue
            }

            if current.count >= hardChunkLength {
                flush()
            }
        }

        flush()

        let mergedTinyParts = mergeTinyTextParts(rawParts)
        return mergedTinyParts.isEmpty ? [text] : mergedTinyParts
    }

    private static func mergeTinyTextParts(_ parts: [String]) -> [String] {
        guard !parts.isEmpty else { return [] }

        var merged: [String] = []

        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if var previous = merged.last,
               (trimmed.count < minChunkLength || previous.count < minChunkLength),
               previous.count + trimmed.count <= hardChunkLength {
                previous += trimmed
                merged[merged.count - 1] = previous
            } else {
                merged.append(trimmed)
            }
        }

        return merged
    }

    private static func mergeContinuationSegments(_ segments: [SubtitleSegment]) -> [SubtitleSegment] {
        guard !segments.isEmpty else { return [] }

        var merged: [SubtitleSegment] = []

        for segment in segments {
            guard let normalized = normalize(segment) else { continue }

            if var last = merged.last,
               shouldMergeContinuation(last: last, next: normalized) {
                last.end = max(last.end, normalized.end)
                last.text = joinedText(last.text, normalized.text)
                last.words = mergedWords(last.words, normalized.words)
                merged[merged.count - 1] = last
                continue
            }

            merged.append(normalized)
        }

        return merged
    }

    private static func shouldMergeContinuation(last: SubtitleSegment, next: SubtitleSegment) -> Bool {
        let gap = next.start - last.end
        let combinedDuration = next.end - last.start
        let combinedLength = last.text.count + next.text.count

        guard gap <= mergeGap,
              combinedDuration <= continuationDuration,
              combinedLength <= continuationLength
        else {
            return false
        }

        if endsStrongly(last.text) {
            return false
        }

        if endsSoftly(last.text), !isVeryShort(last) {
            return false
        }

        return true
    }

    private static func mergeShortSegments(_ segments: [SubtitleSegment]) -> [SubtitleSegment] {
        guard !segments.isEmpty else { return [] }

        var merged: [SubtitleSegment] = []

        for segment in segments {
            guard var normalized = normalize(segment) else { continue }

            if var last = merged.last,
               shouldMerge(last: last, next: normalized) {
                last.end = max(last.end, normalized.end)
                last.text = joinedText(last.text, normalized.text)
                last.words = mergedWords(last.words, normalized.words)
                merged[merged.count - 1] = last
                continue
            }

            if isVeryShort(normalized), merged.isEmpty == false {
                var last = merged.removeLast()
                last.end = max(last.end, normalized.end)
                last.text = joinedText(last.text, normalized.text)
                last.words = mergedWords(last.words, normalized.words)
                merged.append(last)
                continue
            }

            normalized.end = max(normalized.end, normalized.start + 0.1)
            merged.append(normalized)
        }

        return merged
    }

    private static func shouldMerge(last: SubtitleSegment, next: SubtitleSegment) -> Bool {
        let gap = next.start - last.end
        let combinedDuration = next.end - last.start
        let combinedLength = last.text.count + next.text.count

        if gap > mergeGap || combinedDuration > hardDuration || combinedLength > hardChunkLength {
            return false
        }

        if isVeryShort(next) || isVeryShort(last) {
            return !endsStrongly(last.text) || combinedDuration <= preferredDuration
        }

        return false
    }

    private static func isVeryShort(_ segment: SubtitleSegment) -> Bool {
        let duration = segment.end - segment.start
        return duration < minDuration || segment.text.count < minChunkLength
    }

    private static func endsStrongly(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).last.map { strongBreaks.contains($0) } ?? false
    }

    private static func endsSoftly(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).last.map { softBreaks.contains($0) } ?? false
    }

    private static func containsBreak(in text: String) -> Bool {
        text.contains { strongBreaks.contains($0) || softBreaks.contains($0) }
    }

    private static func joinedText(_ left: String, _ right: String) -> String {
        let trimmedLeft = left.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRight = right.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedLeft.isEmpty else { return trimmedRight }
        guard !trimmedRight.isEmpty else { return trimmedLeft }

        if shouldInsertSpaceBetween(trimmedLeft.last, trimmedRight.first) {
            return "\(trimmedLeft) \(trimmedRight)"
        }

        return trimmedLeft + trimmedRight
    }

    private static func mergedWords(_ left: [SubtitleWord]?, _ right: [SubtitleWord]?) -> [SubtitleWord]? {
        let merged = (left ?? []) + (right ?? [])
        return merged.isEmpty ? nil : merged
    }

    private static func shouldInsertSpaceBetween(_ left: Character?, _ right: Character?) -> Bool {
        guard let leftScalar = left?.unicodeScalars.last,
              let rightScalar = right?.unicodeScalars.first
        else {
            return false
        }

        return leftScalar.isASCIIAlphaNumeric && rightScalar.isASCIIAlphaNumeric
    }
}

private extension UnicodeScalar {
    var isASCIIAlphaNumeric: Bool {
        ("a"..."z").contains(self) || ("A"..."Z").contains(self) || ("0"..."9").contains(self)
    }
}
