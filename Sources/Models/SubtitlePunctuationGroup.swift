import Foundation

enum SubtitlePunctuationGroup: String, CaseIterable, Codable, Hashable, Identifiable {
    case period
    case comma
    case questionMark
    case exclamationMark
    case ellipsis
    case semicolon
    case colon
    case enumerationComma
    case quotes
    case brackets
    case dash
    case bookTitle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .period: "句号"
        case .comma: "逗号"
        case .questionMark: "问号"
        case .exclamationMark: "感叹号"
        case .ellipsis: "省略号"
        case .semicolon: "分号"
        case .colon: "冒号"
        case .enumerationComma: "顿号"
        case .quotes: "引号"
        case .brackets: "括号"
        case .dash: "破折号"
        case .bookTitle: "书名号"
        }
    }

    var example: String {
        switch self {
        case .period: "。."
        case .comma: "，,"
        case .questionMark: "？?"
        case .exclamationMark: "！!"
        case .ellipsis: "…… ..."
        case .semicolon: "；;"
        case .colon: "：:"
        case .enumerationComma: "、"
        case .quotes: "“”「」"
        case .brackets: "（）()"
        case .dash: "—— -"
        case .bookTitle: "《》"
        }
    }

    static let subtitleRecommended: Set<Self> = [
        .questionMark, .exclamationMark, .ellipsis
    ]

    static let structural: Set<Self> = subtitleRecommended.union([
        .colon, .enumerationComma
    ])
}

enum HotwordPromptPreference: String, Codable {
    case undecided
    case enabled
    case disabled
}
