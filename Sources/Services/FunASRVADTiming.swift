import Foundation

struct FunASRVADInterval: Equatable {
    var start: TimeInterval
    var end: TimeInterval

    var duration: TimeInterval {
        max(end - start, 0)
    }
}

enum FunASRVADParser {
    /// 解析 `llama-funasr-vad` stdout：每行 `start_ms end_ms`（或一行多个 pair）。
    static func parse(stdout: String, fullDuration: TimeInterval) -> [FunASRVADInterval] {
        let duration = max(fullDuration, 0.1)
        var pairs: [(Double, Double)] = []
        let numbers = stdout
            .split { $0.isWhitespace || $0.isNewline }
            .compactMap { Double($0) }

        var index = 0
        while index + 1 < numbers.count {
            let startMs = numbers[index]
            let endMs = numbers[index + 1]
            index += 2
            guard endMs > startMs else { continue }
            pairs.append((startMs / 1000.0, endMs / 1000.0))
        }

        let intervals = pairs
            .map { start, end in
                FunASRVADInterval(
                    start: min(max(0, start), duration),
                    end: min(max(0, end), duration)
                )
            }
            .filter { $0.duration >= 0.08 }
            .sorted { $0.start < $1.start }

        return mergeOverlapping(intervals)
    }

    private static func mergeOverlapping(_ input: [FunASRVADInterval]) -> [FunASRVADInterval] {
        guard var current = input.first else { return [] }
        var result: [FunASRVADInterval] = []
        for next in input.dropFirst() {
            if next.start <= current.end + 0.05 {
                current.end = max(current.end, next.end)
            } else {
                result.append(current)
                current = next
            }
        }
        result.append(current)
        return result
    }
}

/// 把整段识别文本按 VAD 人声区间时长比例铺开（仍非字级对齐，但静音不再吃掉时间轴）。
enum FunASRTimingMapper {
    static func coarseSegments(
        text: String,
        intervals: [FunASRVADInterval],
        fullDuration: TimeInterval
    ) -> [SubtitleSegment] {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return [] }

        let duration = max(fullDuration, 0.1)
        let usable = intervals.filter { $0.duration >= 0.08 && $0.start < duration }
        guard !usable.isEmpty else {
            return [SubtitleSegment(start: 0, end: duration, text: cleaned)]
        }

        let tokens = lexicalTokens(cleaned)
        guard !tokens.isEmpty else {
            return [SubtitleSegment(start: 0, end: duration, text: cleaned)]
        }

        let totalSpeech = usable.reduce(0.0) { $0 + $1.duration }
        guard totalSpeech > 0.05 else {
            return [SubtitleSegment(start: 0, end: duration, text: cleaned)]
        }

        let totalUnits = max(tokens.reduce(0) { $0 + max($1.count, 1) }, 1)
        var tokenIndex = 0
        var segments: [SubtitleSegment] = []

        for (intervalIndex, interval) in usable.enumerated() {
            let isLast = intervalIndex == usable.count - 1
            let remainingUnits = tokens.suffix(from: tokenIndex).reduce(0) { $0 + max($1.count, 1) }
            let remainingIntervals = usable.count - intervalIndex
            let share = interval.duration / totalSpeech
            let proportional = max(1, Int((Double(totalUnits) * share).rounded()))
            // 非最后一段：按比例取字，但至少 1 个 unit，且给后面区间留字
            let targetUnits: Int
            if isLast {
                targetUnits = remainingUnits
            } else {
                let reserveForRest = max(remainingIntervals - 1, 0)
                targetUnits = min(proportional, max(remainingUnits - reserveForRest, 1))
            }

            var chunkTokens: [String] = []
            var chunkUnits = 0
            while tokenIndex < tokens.count {
                let token = tokens[tokenIndex]
                let units = max(token.count, 1)
                if !isLast, !chunkTokens.isEmpty, chunkUnits >= targetUnits {
                    break
                }
                if !isLast, !chunkTokens.isEmpty, chunkUnits + units > targetUnits, remainingUnits - chunkUnits > 0 {
                    break
                }
                chunkTokens.append(token)
                chunkUnits += units
                tokenIndex += 1
                if !isLast, chunkUnits >= targetUnits {
                    break
                }
            }

            if chunkTokens.isEmpty {
                continue
            }

            let chunkText = joinTokens(chunkTokens)
            guard !chunkText.isEmpty else { continue }
            segments.append(
                SubtitleSegment(
                    start: interval.start,
                    end: max(interval.end, interval.start + 0.1),
                    text: chunkText
                )
            )
        }

        // 若还有剩余字，并入最后一区间
        if tokenIndex < tokens.count {
            let rest = joinTokens(Array(tokens[tokenIndex...]))
            if !rest.isEmpty {
                if var last = segments.last {
                    last.text += rest
                    segments[segments.count - 1] = last
                } else if let lastInterval = usable.last {
                    segments.append(
                        SubtitleSegment(
                            start: lastInterval.start,
                            end: max(lastInterval.end, lastInterval.start + 0.1),
                            text: rest
                        )
                    )
                }
            }
        }

        return segments.isEmpty
            ? [SubtitleSegment(start: 0, end: duration, text: cleaned)]
            : segments
    }

    private static func lexicalTokens(_ text: String) -> [String] {
        var tokens: [String] = []
        var latinWord = ""

        func flushLatin() {
            guard !latinWord.isEmpty else { return }
            tokens.append(latinWord)
            latinWord = ""
        }

        for character in text {
            if character.isASCIIWordCharacter {
                latinWord.append(character)
            } else {
                flushLatin()
                if !character.isWhitespace {
                    tokens.append(String(character))
                }
            }
        }
        flushLatin()
        return tokens
    }

    private static func joinTokens(_ tokens: [String]) -> String {
        var result = ""
        for token in tokens {
            if shouldInsertSpace(result.last, token.first) {
                result.append(" ")
            }
            result.append(token)
        }
        return result
    }

    private static func shouldInsertSpace(_ left: Character?, _ right: Character?) -> Bool {
        guard let left, let right else { return false }
        return left.isASCIIWordCharacter && right.isASCIIWordCharacter
    }
}

private extension Character {
    var isASCIIWordCharacter: Bool {
        unicodeScalars.allSatisfy { scalar in
            ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar)
                || ("0"..."9").contains(scalar) || scalar == "'"
        }
    }
}
