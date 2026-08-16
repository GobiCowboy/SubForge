import Foundation

extension TimedSubtitleSegmenter {
    static let minimumEffectiveCharacters = 3
    private static let primaryBreaks: Set<Character> = [
        "。", "！", "？", "!", "?", "；", ";", "，", ","
    ]
    private static let fallbackBreaks: Set<Character> = ["、", "：", ":"]

    static func segmentSources(
        _ sources: [SubtitleSegment],
        configuration: SubtitleSegmentationConfiguration
    ) -> [SubtitleSegment] {
        let results = sources.flatMap { source -> [SubtitleSegment] in
            if let words = source.words, !words.isEmpty {
                return segmentWordsWithinSource(
                    words,
                    configuration: configuration,
                    expandCoarseTokens: false
                )
            }
            let coarse = SubtitleWord(start: source.start, end: source.end, text: source.text)
            return segmentWordsWithinSource(
                [coarse],
                configuration: configuration,
                expandCoarseTokens: true
            )
        }
        return removeOverlaps(results)
    }

    static func segmentWordsWithinSource(
        _ input: [SubtitleWord],
        configuration: SubtitleSegmentationConfiguration,
        expandCoarseTokens: Bool
    ) -> [SubtitleSegment] {
        let boundaryWords = input.flatMap(splitAtPunctuationBoundaries)
        let words = semanticWords(
            boundaryWords,
            configuration: configuration,
            expandCoarseTokens: expandCoarseTokens
        )
        guard !words.isEmpty else { return [] }

        var primaryChunks: [[SubtitleWord]] = []
        var current: [SubtitleWord] = []
        for word in words {
            current.append(word)
            if endsAtPrimaryBoundary(word.text) {
                primaryChunks.append(current)
                current = []
            }
        }
        if !current.isEmpty {
            primaryChunks.append(current)
        }

        let limited = primaryChunks.flatMap {
            splitOverlong($0, configuration: configuration)
        }
        let merged = mergeShortChunks(limited, configuration: configuration)
        return removeOverlaps(merged.compactMap(makeSegment))
    }

    private static func splitAtPunctuationBoundaries(_ word: SubtitleWord) -> [SubtitleWord] {
        let text = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        var pieces: [String] = []
        var current = ""
        let characters = Array(text)

        for index in characters.indices {
            let character = characters[index]
            current.append(character)
            if isBoundary(character, at: index, in: characters) {
                pieces.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            pieces.append(current)
        }
        guard pieces.count > 1 else { return [word] }

        let totalUnits = max(pieces.reduce(0) { $0 + max($1.count, 1) }, 1)
        let duration = max(word.end - word.start, 0.01)
        var cursor = word.start
        return pieces.enumerated().map { index, piece in
            let end: TimeInterval
            if index == pieces.count - 1 {
                end = word.end
            } else {
                let ratio = Double(max(piece.count, 1)) / Double(totalUnits)
                end = min(word.end, cursor + duration * ratio)
            }
            defer { cursor = end }
            return SubtitleWord(start: cursor, end: max(end, cursor + 0.005), text: piece)
        }
    }

    private static func isBoundary(
        _ character: Character,
        at index: Int,
        in characters: [Character]
    ) -> Bool {
        if primaryBreaks.contains(character) || fallbackBreaks.contains(character) {
            return true
        }
        guard character == "." else { return false }
        let previousIsAlphaNumeric = index > 0 && characters[index - 1].isTimedASCIIWordCharacter
        let nextIsAlphaNumeric = index + 1 < characters.count
            && characters[index + 1].isTimedASCIIWordCharacter
        return !(previousIsAlphaNumeric && nextIsAlphaNumeric)
    }

    private static func endsAtPrimaryBoundary(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return primaryBreaks.contains(last) || last == "."
    }

    private static func endsAtFallbackBoundary(_ text: String) -> Bool {
        text.last.map(fallbackBreaks.contains) ?? false
    }

    private static func splitOverlong(
        _ words: [SubtitleWord],
        configuration: SubtitleSegmentationConfiguration
    ) -> [[SubtitleWord]] {
        var output: [[SubtitleWord]] = []
        var buffer: [SubtitleWord] = []

        for word in words {
            buffer.append(word)
            while SubtitleEffectiveLength.count(buffer) > configuration.maxCharacters {
                guard let breakIndex = breakIndex(
                    in: buffer,
                    maxCharacters: configuration.maxCharacters
                ) else {
                    output.append(buffer)
                    buffer = []
                    break
                }
                output.append(Array(buffer.prefix(breakIndex)))
                buffer.removeFirst(breakIndex)
            }
        }
        if !buffer.isEmpty {
            output.append(buffer)
        }
        return output
    }

    private static func breakIndex(
        in words: [SubtitleWord],
        maxCharacters: Int
    ) -> Int? {
        guard words.count > 1 else { return nil }
        let candidates = (1..<words.count).filter { index in
            let prefix = Array(words.prefix(index))
            let remainder = Array(words.dropFirst(index))
            let prefixLength = SubtitleEffectiveLength.count(prefix)
            let remainderLength = SubtitleEffectiveLength.count(remainder)
            return prefixLength > 0
                && prefixLength <= maxCharacters
                && (remainderLength == 0 || remainderLength >= minimumEffectiveCharacters)
        }
        let usable = candidates.isEmpty
            ? (1..<words.count).filter {
                SubtitleEffectiveLength.count(Array(words.prefix($0))) <= maxCharacters
            }
            : candidates
        guard !usable.isEmpty else { return nil }

        let fallback = usable.filter {
            endsAtFallbackBoundary(words[$0 - 1].text)
        }
        if !fallback.isEmpty {
            return fallback.max()
        }
        let natural = usable.filter { index in
            let ending = words[index - 1].text.trimmingCharacters(in: .whitespacesAndNewlines)
            return !weakLineEndWords.contains(ending)
        }
        return (natural.isEmpty ? usable : natural).max()
    }

    private static func mergeShortChunks(
        _ chunks: [[SubtitleWord]],
        configuration: SubtitleSegmentationConfiguration
    ) -> [[SubtitleWord]] {
        guard !chunks.isEmpty else { return [] }
        var merged: [[SubtitleWord]] = []
        var index = 0

        while index < chunks.count {
            var chunk = chunks[index]
            if SubtitleEffectiveLength.count(chunk) < minimumEffectiveCharacters,
               index + 1 < chunks.count {
                chunk.append(contentsOf: chunks[index + 1])
                merged.append(contentsOf: splitOverlong(chunk, configuration: configuration))
                index += 2
            } else {
                merged.append(chunk)
                index += 1
            }
        }

        if merged.count > 1,
           let last = merged.last,
           SubtitleEffectiveLength.count(last) < minimumEffectiveCharacters {
            let combined = merged[merged.count - 2] + last
            merged.removeLast(2)
            merged.append(contentsOf: splitOverlong(combined, configuration: configuration))
        }
        return merged
    }

    private static func makeSegment(_ words: [SubtitleWord]) -> SubtitleSegment? {
        guard let first = words.first, let last = words.last else { return nil }
        let text = joinedText(words).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return SubtitleSegment(
            start: first.start,
            end: max(last.end, first.start + 0.1),
            text: text,
            words: words
        )
    }
}
