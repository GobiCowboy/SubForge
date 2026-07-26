import Foundation
import NaturalLanguage

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
            var bestScore = -Double.greatestFiniteMagnitude
            for candidate in lower...upper {
                let length = pieceLengths.prefix(candidate).reduce(0, +)
                let distance = abs(Double(length) - target)
                let previousPiece = pieces[candidate - 1]
                let boundaryBonus: Double
                if isStrongCorrectionBoundary(previousPiece) {
                    boundaryBonus = 1_200
                } else if isSoftCorrectionBoundary(previousPiece) {
                    boundaryBonus = 520
                } else {
                    boundaryBonus = 0
                }

                // 先满足时间比例，再尽量把边界落在校对文本的自然断句处。
                // 这能避免“但是/所以/然后”等连接结构被长度刀口切开。
                let score = boundaryBonus - distance
                if score > bestScore {
                    best = candidate
                    bestScore = score
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

    static func isStrongCorrectionBoundary(_ piece: String) -> Bool {
        piece.last.map { strongBreaks.contains($0) } ?? false
    }

    static func isSoftCorrectionBoundary(_ piece: String) -> Bool {
        piece.last.map { softBreaks.contains($0) } ?? false
    }

    /// 最大字数是排版目标，不是字符刀。超过目标时在附近的自然词边界回退，
    /// 宁可让一个不可拆的专名略微超出，也不把词组或英文名称劈开。
    static func preferredBreakIndex(
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
}
