import Foundation

struct SubtitleWord: Equatable, Codable {
    var start: TimeInterval
    var end: TimeInterval
    var text: String
}

struct SubtitleSegment: Identifiable, Equatable, Codable {
    let id: UUID
    var start: TimeInterval
    var end: TimeInterval
    var text: String
    var words: [SubtitleWord]?

    init(
        id: UUID = UUID(),
        start: TimeInterval,
        end: TimeInterval,
        text: String,
        words: [SubtitleWord]? = nil
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.words = words
    }
}
