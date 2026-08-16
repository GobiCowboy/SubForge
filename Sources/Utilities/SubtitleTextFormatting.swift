import Foundation

enum SubtitleTextFormatting {
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

    static func applyingPunctuationPolicy(
        _ text: String,
        retained: Set<SubtitlePunctuationGroup>
    ) -> String {
        var output = ""
        var index = text.startIndex

        while index < text.endIndex {
            if text[index...].hasPrefix("……") {
                appendPunctuation("……", group: .ellipsis, retained: retained, to: &output)
                index = text.index(index, offsetBy: 2)
                continue
            }
            if text[index...].hasPrefix("...") {
                appendPunctuation("...", group: .ellipsis, retained: retained, to: &output)
                index = text.index(index, offsetBy: 3)
                continue
            }

            let character = text[index]
            if let group = punctuationGroup(for: character) {
                appendPunctuation(String(character), group: group, retained: retained, to: &output)
            } else if character.isSubtitlePunctuation {
                appendSpace(to: &output)
            } else if character.isWhitespace {
                appendSpace(to: &output)
            } else {
                output.append(character)
            }
            index = text.index(after: index)
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func appendPunctuation(
        _ punctuation: String,
        group: SubtitlePunctuationGroup,
        retained: Set<SubtitlePunctuationGroup>,
        to output: inout String
    ) {
        if retained.contains(group) {
            output.append(punctuation)
        } else {
            appendSpace(to: &output)
        }
    }

    private static func appendSpace(to output: inout String) {
        guard !output.isEmpty, output.last != " " else { return }
        output.append(" ")
    }

    private static func punctuationGroup(for character: Character) -> SubtitlePunctuationGroup? {
        switch character {
        case "。", "．", ".": .period
        case "，", ",": .comma
        case "？", "?": .questionMark
        case "！", "!": .exclamationMark
        case "…": .ellipsis
        case "；", ";": .semicolon
        case "：", ":": .colon
        case "、", "・", "·": .enumerationComma
        case "“", "”", "‘", "’", "\"", "'", "「", "」", "『", "』": .quotes
        case "（", "）", "(", ")", "【", "】", "[", "]", "〔", "〕", "{", "}": .brackets
        case "—", "–", "-": .dash
        case "《", "》", "〈", "〉": .bookTitle
        default: nil
        }
    }
}
