import Foundation

/// SRT 字幕格式解析与生成
enum SRTParser {
    /// 解析 SRT 文件内容为字幕分段
    static func parse(_ content: String) -> [SubtitleSegment] {
        var segments: [SubtitleSegment] = []
        // 按空行分割块
        let blocks = content.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

        for block in blocks {
            let lines = block.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard lines.count >= 2 else { continue }

            // 找时间码行（包含 -->）
            guard let timeLineIdx = lines.firstIndex(where: { $0.contains("-->") }),
                  timeLineIdx + 1 < lines.count else { continue }

            let timeParts = lines[timeLineIdx].components(separatedBy: "-->").map { $0.trimmingCharacters(in: .whitespaces) }
            guard timeParts.count == 2,
                  let start = parseTime(timeParts[0]),
                  let end = parseTime(timeParts[1]) else { continue }

            let text = lines[(timeLineIdx + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            segments.append(SubtitleSegment(start: start, end: end, text: text))
        }

        return segments
    }

    /// 生成 SRT 格式内容
    static func generate(_ segments: [SubtitleSegment]) -> String {
        segments.enumerated().map { index, seg in
            let idx = index + 1
            let start = formatSRTTime(seg.start)
            let end = formatSRTTime(seg.end)
            return "\(idx)\n\(start) --> \(end)\n\(seg.text)"
        }.joined(separator: "\n\n") + "\n"
    }

    // MARK: - 时间格式化

    private static func formatSRTTime(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }

    private static func parseTime(_ string: String) -> TimeInterval? {
        let cleaned = string.trimmingCharacters(in: .whitespaces)
        let parts = cleaned.components(separatedBy: CharacterSet(charactersIn: ",."))
        guard parts.count == 2 else { return nil }
        let timeParts = parts[0].components(separatedBy: ":")
        guard timeParts.count == 3,
              let h = Double(timeParts[0]),
              let m = Double(timeParts[1]),
              let s = Double(timeParts[2]) else { return nil }
        let msStr = String(parts[1].prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
        let ms = Double(msStr) ?? 0
        let total = h * 3600.0 + m * 60.0 + s + ms / 1000.0
        return total
    }
}
