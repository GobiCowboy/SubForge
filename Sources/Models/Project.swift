import Foundation

/// 项目状态（当前打开的文件）
struct Project {
    var audioURL: URL
    var srtURL: URL?
    var fcpxmlURL: URL?

    init(audioURL: URL) {
        self.audioURL = audioURL
        self.srtURL = audioURL.deletingPathExtension().appendingPathExtension("srt")
    }
}
