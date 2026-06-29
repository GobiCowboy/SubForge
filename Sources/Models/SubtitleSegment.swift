import Foundation

struct SubtitleSegment: Identifiable, Equatable, Codable {
    let id: UUID
    var start: TimeInterval
    var end: TimeInterval
    var text: String

    init(id: UUID = UUID(), start: TimeInterval, end: TimeInterval, text: String) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
    }
}
