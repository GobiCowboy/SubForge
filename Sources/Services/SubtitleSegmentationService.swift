import Foundation

enum SubtitleSegmentationService {
    private static let strongBreaks: Set<Character> = ["。", "！", "？", "!", "?", ";", "；"]
    private static let softBreaks: Set<Character> = ["，", ",", "、", "：", ":", "—", "–"]
    private static let minChunkLength = 4
    private static let preferredChunkLength = 18
    private static let hardChunkLength = 28
    private static let minDuration: TimeInterval = 0.9
    private static let preferredDuration: TimeInterval = 3.6
    private static let hardDuration: TimeInterval = 5.2
    private static let mergeGap: TimeInterval = 0.35

    static func refine(_ segments: [SubtitleSegment]) -> [SubtitleSegment] {
        let normalized = segments.compactMap(normalize)
        guard !normalized.isEmpty else { return [] }

        let split = normalized.flatMap(splitIfNeeded)
        let merged = mergeShortSegments(split)

        return merged
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
        guard duration > hardDuration || text.count > hardChunkLength else {
            return [segment]
        }

        let parts = chunkText(text)
        guard parts.count > 1 else {
            return [segment]
        }

        let totalUnits = max(parts.reduce(0) { $0 + max($1.count, 1) }, 1)
        var cursor = segment.start

        return parts.enumerated().map { index, part in
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

            if softBreaks.contains(character), current.count >= 12 {
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

    private static func mergeShortSegments(_ segments: [SubtitleSegment]) -> [SubtitleSegment] {
        guard !segments.isEmpty else { return [] }

        var merged: [SubtitleSegment] = []

        for segment in segments {
            guard var normalized = normalize(segment) else { continue }

            if var last = merged.last,
               shouldMerge(last: last, next: normalized) {
                last.end = max(last.end, normalized.end)
                last.text += normalized.text
                merged[merged.count - 1] = last
                continue
            }

            if isVeryShort(normalized), merged.isEmpty == false {
                var last = merged.removeLast()
                last.end = max(last.end, normalized.end)
                last.text += normalized.text
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
        let lastEndsStrongly = last.text.last.map { strongBreaks.contains($0) } ?? false

        if gap > mergeGap || combinedDuration > hardDuration || combinedLength > hardChunkLength {
            return false
        }

        if isVeryShort(next) || isVeryShort(last) {
            return !lastEndsStrongly || combinedDuration <= preferredDuration
        }

        return false
    }

    private static func isVeryShort(_ segment: SubtitleSegment) -> Bool {
        let duration = segment.end - segment.start
        return duration < minDuration || segment.text.count < minChunkLength
    }
}
