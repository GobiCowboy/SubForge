import Foundation

struct RecentProject: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var path: String
    var kind: String
    var durationLabel: String
    var modifiedLabel: String
    var subtitleCount: Int

    init(
        id: UUID = UUID(),
        name: String,
        path: String,
        kind: String,
        durationLabel: String,
        modifiedLabel: String,
        subtitleCount: Int
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.kind = kind
        self.durationLabel = durationLabel
        self.modifiedLabel = modifiedLabel
        self.subtitleCount = subtitleCount
    }

    static let samples: [RecentProject] = [
        .init(
            name: "Marketing_Campaign_v2_Final.mp4",
            path: "/tmp/Marketing_Campaign_v2_Final.mp4",
            kind: "video",
            durationLabel: "24:00",
            modifiedLabel: "今天",
            subtitleCount: 132
        ),
        .init(
            name: "Podcast_Episode_014.wav",
            path: "/tmp/Podcast_Episode_014.wav",
            kind: "audio",
            durationLabel: "58:20",
            modifiedLabel: "昨天",
            subtitleCount: 406
        ),
        .init(
            name: "Brand_Film_Cutdown.srt",
            path: "/tmp/Brand_Film_Cutdown.srt",
            kind: "srt",
            durationLabel: "03:41",
            modifiedLabel: "2 天前",
            subtitleCount: 48
        ),
    ]
}
