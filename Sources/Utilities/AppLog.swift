import Foundation
import OSLog

enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "SubForge"

    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    static let editor = Logger(subsystem: subsystem, category: "editor")
    static let transcription = Logger(subsystem: subsystem, category: "transcription")
    static let proofreading = Logger(subsystem: subsystem, category: "proofreading")
    static let `import` = Logger(subsystem: subsystem, category: "import")
    static let export = Logger(subsystem: subsystem, category: "export")
    static let watcher = Logger(subsystem: subsystem, category: "watcher")
    static let settings = Logger(subsystem: subsystem, category: "settings")
}
