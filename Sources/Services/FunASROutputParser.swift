import Foundation

/// 解析 `llama-funasr-sensevoice` stdout。
/// 上游 CLI 一期不输出时间戳；支持纯文本与可选带时间前缀行。
enum FunASROutputParser {
    struct ParsedSegment: Equatable {
        var start: TimeInterval?
        var end: TimeInterval?
        var text: String
    }

    /// 清洗 SenseVoice stdout，只保留正文。
    static func plainText(from stdout: String) -> String {
        stripMetaTags(stdout)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("[sensevoice]") }
            .joined(separator: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 去掉 SenseVoice meta tag，并抽取可用文本行。
    static func parse(stdout: String, audioDuration: TimeInterval) -> [SubtitleSegment] {
        let cleanedLines = stripMetaTags(stdout)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("[sensevoice]") }

        guard !cleanedLines.isEmpty else { return [] }

        let timed = cleanedLines.compactMap(parseTimedLine)
        if timed.count == cleanedLines.count, timed.contains(where: { $0.start != nil && $0.end != nil }) {
            return timed.compactMap { item in
                guard let start = item.start, let end = item.end else { return nil }
                let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return SubtitleSegment(start: start, end: max(end, start + 0.1), text: text)
            }
        }

        let fullText = plainText(from: stdout)
        guard !fullText.isEmpty else { return [] }

        let duration = max(audioDuration, 0.5)
        return [SubtitleSegment(start: 0, end: duration, text: fullText)]
    }

    static func stripMetaTags(_ text: String) -> String {
        // <|zh|> / <|NEUTRAL|> / <|Speech|> / <|woitn|> / <|withitn|> 等
        guard let regex = try? NSRegularExpression(pattern: "<\\|[^|]*\\|>", options: []) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    /// 兼容未来可能出现的 `[0.00-1.20] text` 或 `[00:00.00 --> 00:01.20] text`
    private static func parseTimedLine(_ line: String) -> ParsedSegment? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["),
              let close = trimmed.firstIndex(of: "]")
        else {
            return ParsedSegment(start: nil, end: nil, text: trimmed)
        }

        let timePart = String(trimmed[trimmed.index(after: trimmed.startIndex)..<close])
            .trimmingCharacters(in: .whitespaces)
        let text = String(trimmed[trimmed.index(after: close)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let arrow = timePart.range(of: "-->") {
            let start = parseFlexibleTime(String(timePart[..<arrow.lowerBound]))
            let end = parseFlexibleTime(String(timePart[arrow.upperBound...]))
            if let start, let end {
                return ParsedSegment(start: start, end: end, text: text.isEmpty ? trimmed : text)
            }
        }

        if let dash = timePart.range(of: "-", options: [], range: timePart.startIndex..<timePart.endIndex) {
            // 仅当两侧都能解析为秒数时视为时间范围，避免误伤正常文本
            let left = String(timePart[..<dash.lowerBound]).trimmingCharacters(in: .whitespaces)
            let right = String(timePart[dash.upperBound...]).trimmingCharacters(in: .whitespaces)
            if let start = Double(left), let end = Double(right), end >= start {
                return ParsedSegment(start: start, end: end, text: text.isEmpty ? trimmed : text)
            }
        }

        return ParsedSegment(start: nil, end: nil, text: trimmed)
    }

    private static func parseFlexibleTime(_ raw: String) -> TimeInterval? {
        let string = raw.trimmingCharacters(in: .whitespaces)
        if let value = Double(string) {
            return value
        }

        let parts = string.components(separatedBy: ":")
        if parts.count == 2,
           let minutes = Double(parts[0]),
           let seconds = Double(parts[1]) {
            return minutes * 60 + seconds
        }
        if parts.count == 3,
           let hours = Double(parts[0]),
           let minutes = Double(parts[1]),
           let seconds = Double(parts[2]) {
            return hours * 3600 + minutes * 60 + seconds
        }
        return nil
    }
}
