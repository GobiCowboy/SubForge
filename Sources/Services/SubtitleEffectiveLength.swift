import Foundation

enum SubtitleEffectiveLength {
    private static let fillerCharacters: Set<Character> = [
        "嗯", "呃", "额", "哦", "噢", "哎", "唉", "呢", "啊", "呀", "吧", "嘛"
    ]

    static func count(_ text: String) -> Int {
        let characters = Array(text)
        return characters.indices.reduce(into: 0) { total, index in
            let character = characters[index]
            guard !character.isWhitespace, !character.isSubtitlePunctuation else { return }
            guard !fillerCharacters.contains(character) else { return }
            if character == "好", isStandaloneGood(at: index, in: characters) {
                return
            }
            total += 1
        }
    }

    static func count(_ words: [SubtitleWord]) -> Int {
        count(TimedSubtitleSegmenter.joinedText(words))
    }

    private static func isStandaloneGood(at index: Int, in characters: [Character]) -> Bool {
        let leftBoundary = index == characters.startIndex
            || characters[index - 1].isWhitespace
            || characters[index - 1].isSubtitlePunctuation
        let rightBoundary = index == characters.index(before: characters.endIndex)
            || characters[index + 1].isWhitespace
            || characters[index + 1].isSubtitlePunctuation
        return leftBoundary && rightBoundary
    }
}

extension Character {
    var isSubtitlePunctuation: Bool {
        unicodeScalars.allSatisfy { scalar in
            switch scalar.properties.generalCategory {
            case .connectorPunctuation,
                 .dashPunctuation,
                 .closePunctuation,
                 .finalPunctuation,
                 .initialPunctuation,
                 .openPunctuation,
                 .otherPunctuation:
                true
            default:
                false
            }
        }
    }
}
