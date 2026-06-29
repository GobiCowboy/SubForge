import Foundation

enum SettingsTestAsset {
    static let expectedASRText = "本视频耗时一年时间制作，共计一小时55min，58964字，带你认识进入社会学校不教但你要会的53个技能。视频均为主播原创实景拍摄。挑战一天学会一个新技能。"
    static let proofreadingSampleInput = "今天天汽很好，我们去公圆玩吧"

    static func audioURL() -> URL? {
        if let bundled = Bundle.main.url(forResource: "test_audio", withExtension: "m4a") {
            return bundled
        }

        let workspaceFallback = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("BAK/test_audio.m4a")

        if FileManager.default.fileExists(atPath: workspaceFallback.path) {
            return workspaceFallback
        }

        return nil
    }
}
