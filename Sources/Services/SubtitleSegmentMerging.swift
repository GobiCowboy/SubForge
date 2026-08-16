import Foundation

extension SubtitleSegmentationService {
    static func mergeContinuationSegments(_ segments: [SubtitleSegment]) -> [SubtitleSegment] {
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

    static func shouldMergeContinuation(last: SubtitleSegment, next: SubtitleSegment) -> Bool {
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

    static func mergeShortSegments(_ segments: [SubtitleSegment]) -> [SubtitleSegment] {
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

    static func shouldMerge(last: SubtitleSegment, next: SubtitleSegment) -> Bool {
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

    static func isVeryShort(_ segment: SubtitleSegment) -> Bool {
        let duration = segment.end - segment.start
        return duration < minDuration || segment.text.count < minChunkLength
    }

    static func endsStrongly(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).last.map { strongBreaks.contains($0) } ?? false
    }

    static func endsSoftly(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).last.map { softBreaks.contains($0) } ?? false
    }

    static func containsBreak(in text: String) -> Bool {
        text.contains { strongBreaks.contains($0) || softBreaks.contains($0) }
    }

    static func joinedText(_ left: String, _ right: String) -> String {
        let trimmedLeft = left.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRight = right.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedLeft.isEmpty else { return trimmedRight }
        guard !trimmedRight.isEmpty else { return trimmedLeft }

        if shouldInsertSpaceBetween(trimmedLeft.last, trimmedRight.first) {
            return "\(trimmedLeft) \(trimmedRight)"
        }

        return trimmedLeft + trimmedRight
    }

    static func mergedWords(_ left: [SubtitleWord]?, _ right: [SubtitleWord]?) -> [SubtitleWord]? {
        let merged = (left ?? []) + (right ?? [])
        return merged.isEmpty ? nil : merged
    }

    static func shouldInsertSpaceBetween(_ left: Character?, _ right: Character?) -> Bool {
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
