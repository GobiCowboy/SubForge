import Foundation

enum SRTCodec {
    static func parse(_ source: String) -> [SubtitleSegment] {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")
        var segments: [SubtitleSegment] = []

        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard lines.count >= 3 else { continue }
            let timelineLine = lines[1]
            let contentLines = lines.dropFirst(2)

            let parts = timelineLine.components(separatedBy: " --> ")
            guard
                parts.count == 2,
                let start = parseTimestamp(parts[0]),
                let end = parseTimestamp(parts[1])
            else {
                continue
            }

            let text = contentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            segments.append(SubtitleSegment(start: start, end: end, text: text))
        }

        return segments
    }

    static func generate(_ segments: [SubtitleSegment]) -> String {
        segments.enumerated().map { index, segment in
            """
            \(index + 1)
            \(formatTimestamp(segment.start)) --> \(formatTimestamp(segment.end))
            \(segment.text)
            """
        }
        .joined(separator: "\n\n")
    }
}
