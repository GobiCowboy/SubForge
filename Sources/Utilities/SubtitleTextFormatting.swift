import Foundation

enum SubtitleTextFormatting {
    /// 字幕成品不显示标点，但不要在识别/分段前调用，否则会丢失语义边界。
    static func removeSubtitlePunctuation(_ text: String) -> String {
        text.filter { character in
            !character.unicodeScalars.allSatisfy {
                CharacterSet.punctuationCharacters.contains($0)
            }
        }
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 转写后清理：去掉行末「收尾标点」，保留问号、感叹号。可连续去掉多个。
    static func stripTrailingLineEndPunctuation(_ text: String) -> String {
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let removable: Set<Character> = [
            "。", "．", ".",
            "，", ",", "、",
            "；", ";",
            "：", ":",
            "…",
            "～", "~",
            "・", "·"
        ]

        while let last = normalized.last {
            if last == "？" || last == "?" || last == "！" || last == "!" {
                break
            }
            if removable.contains(last) {
                normalized.removeLast()
                normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
            // 英文省略号末尾的点：连续 '.' 整段去掉
            if last == "." {
                while normalized.last == "." {
                    normalized.removeLast()
                }
                normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
            break
        }

        return normalized
    }
}
