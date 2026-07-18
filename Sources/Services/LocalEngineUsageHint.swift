import AppKit
import Foundation

/// 本地转写引擎（FunASR / Whisper / Apple）各自在「第一次正式转写」时提示一次。
enum LocalEngineUsageHint {
    private static let defaults = UserDefaults.standard

    private static func defaultsKey(for engine: TranscriptionEngine) -> String? {
        switch engine {
        case .funASRLocal:
            "subforge.hint.firstFormalUse.funASRLocal"
        case .whisperLocal:
            "subforge.hint.firstFormalUse.whisperLocal"
        case .appleSpeech:
            "subforge.hint.firstFormalUse.appleSpeech"
        case .officialSmart, .cloudASR:
            nil
        }
    }

    static func shouldPresent(for engine: TranscriptionEngine) -> Bool {
        guard let key = defaultsKey(for: engine) else { return false }
        return !defaults.bool(forKey: key)
    }

    /// - Returns: 是否继续转写（用户点「继续」为 true；「去配置云端」为 false 并打开设置）
    @MainActor
    static func presentIfNeeded(for engine: TranscriptionEngine) async -> Bool {
        guard shouldPresent(for: engine), let key = defaultsKey(for: engine) else {
            return true
        }

        let engineLabel: String
        switch engine {
        case .funASRLocal:
            engineLabel = "本地 FunASR"
        case .whisperLocal:
            engineLabel = "本地 Whisper"
        case .appleSpeech:
            engineLabel = "Apple 语音"
        case .officialSmart, .cloudASR:
            return true
        }

        let alert = NSAlert()
        alert.messageText = "关于\(engineLabel)"
        alert.informativeText = """
        本地转写适合离线快速出字和草稿处理，时间轴多为估算，交片前请校对字幕与口型。

        若需要更准确的识别与时间对齐，建议在设置中使用云端 ASR。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "继续使用本地")
        alert.addButton(withTitle: "去配置云端")

        let response = alert.runModal()
        defaults.set(true, forKey: key)

        if response == .alertSecondButtonReturn {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            NSApp.activate(ignoringOtherApps: true)
            return false
        }
        return true
    }
}
