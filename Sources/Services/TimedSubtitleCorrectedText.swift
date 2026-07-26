import Foundation

extension TimedSubtitleSegmenter {
    static func segmentPreservingCorrectedText(
        _ input: [SubtitleSegment],
        configuration: SubtitleSegmentationConfiguration
    ) -> [SubtitleSegment] {
        let results = input.flatMap { source -> [SubtitleSegment] in
            guard let sourceWords = source.words, !sourceWords.isEmpty else {
                return segmentEstimated([source], configuration: configuration)
            }
            let timed = segment(sourceWords, configuration: configuration)
            guard !timed.isEmpty else { return [] }

            let corrected = source.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let recognized = joinedText(sourceWords)
            if normalizedComparisonText(corrected) == normalizedComparisonText(recognized) {
                return timed
            }

            guard let chunks = correctedTextChunks(
                corrected,
                weights: timed.map { max($0.text.count, 1) }
            ), chunks.count == timed.count else {
                return segmentEstimated([source], configuration: configuration)
            }

            return zip(timed, chunks).map { timedSegment, text in
                SubtitleSegment(
                    start: timedSegment.start,
                    end: timedSegment.end,
                    text: text
                )
            }
        }
        return removeOverlaps(results)
    }

    static func normalizedComparisonText(_ text: String) -> String {
        text.filter { !$0.isWhitespace }
    }

    static func correctedTextChunks(_ text: String, weights: [Int]) -> [String]? {
        guard !text.isEmpty, !weights.isEmpty else { return nil }
        if weights.count == 1 { return [text] }

        let pieces = lexicalPieces(text).map(\.text)
        guard pieces.count >= weights.count else { return nil }

        let totalWeight = max(weights.reduce(0, +), 1)
        let pieceLengths = pieces.map { max($0.count, 1) }
        let totalLength = max(pieceLengths.reduce(0, +), 1)
        var boundaries: [Int] = [0]
        var consumedWeight = 0
        var previousBoundary = 0

        for groupIndex in 0..<(weights.count - 1) {
            consumedWeight += weights[groupIndex]
            let target = Double(totalLength) * Double(consumedWeight) / Double(totalWeight)
            let remainingGroups = weights.count - groupIndex - 1
            let lower = previousBoundary + 1
            let upper = pieces.count - remainingGroups
            guard lower <= upper else { return nil }

            var best = lower
            var bestDistance = Double.greatestFiniteMagnitude
            for candidate in lower...upper {
                let length = pieceLengths.prefix(candidate).reduce(0, +)
                let distance = abs(Double(length) - target)
                if distance < bestDistance {
                    best = candidate
                    bestDistance = distance
                }
            }
            boundaries.append(best)
            previousBoundary = best
        }
        boundaries.append(pieces.count)

        return zip(boundaries, boundaries.dropFirst()).map { lower, upper in
            joinedText(pieces[lower..<upper].map {
                SubtitleWord(start: 0, end: 0.01, text: $0)
            })
        }
    }
}
