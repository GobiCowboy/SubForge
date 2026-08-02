import Foundation

enum UsageAndUpdatesSection: String, CaseIterable, Identifiable {
    case help = "使用帮助"
    case news = "最新动态"
    case updates = "检查更新"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .help: "questionmark.circle"
        case .news: "sparkles"
        case .updates: "arrow.down.circle"
        }
    }
}

struct AppVersion: Comparable, Codable, Hashable, Sendable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ value: String) {
        let components = value
            .split(separator: ".", omittingEmptySubsequences: false)

        guard (1...3).contains(components.count),
              components.allSatisfy({ $0.allSatisfy(\.isNumber) }),
              let major = Int(components[0]),
              let minor = components.count > 1 ? Int(components[1]) : 0,
              let patch = components.count > 2 ? Int(components[2]) : 0,
              major >= 0, minor >= 0, patch >= 0 else {
            return nil
        }

        self.major = major
        self.minor = minor
        self.patch = patch
    }

    var description: String { "\(major).\(minor).\(patch)" }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

enum AppDistributionChannel: String, Codable, CaseIterable, Sendable {
    case local
    case developerID = "developer-id"
    case appStore = "app-store"

    var title: String {
        switch self {
        case .local: "开发版本"
        case .developerID: "站外版本"
        case .appStore: "App Store 版本"
        }
    }
}

struct VersionContentChannel: Codable, Sendable {
    let latestVersion: String
    let downloadURL: String?
}

struct VersionContentManifest: Codable, Sendable {
    let schemaVersion: Int
    let appID: String
    let latestVersion: String
    let storeURL: String?
    let channels: [String: VersionContentChannel]
    let releases: [VersionReleaseIndex]
}

struct VersionReleaseIndex: Codable, Identifiable, Sendable {
    let version: String
    let releaseURL: String
    let releaseSHA256: String?
    let helpVersion: String
    let helpURL: String
    let helpSHA256: String?

    var id: String { version }
}

struct VersionReleaseNote: Codable, Identifiable, Sendable {
    let version: String
    let title: String
    let publishedAt: String
    let highlights: [String]
    let videoURL: String?

    var id: String { version }
}

struct VersionHelpDocument: Codable, Identifiable, Sendable {
    let version: String
    let title: String
    let sections: [VersionHelpSection]

    var id: String { version }
}

struct VersionHelpSection: Codable, Identifiable, Sendable {
    let title: String
    let body: String
    let bullets: [String]

    var id: String { title }
}

struct VersionUpdateNotice: Equatable, Sendable {
    let latestVersion: String
    let title: String
    let highlights: [String]
}

enum VersionContentState: Equatable {
    case idle
    case checking
    case current
    case available
    case failed(String)

    var title: String {
        switch self {
        case .idle: "尚未检查"
        case .checking: "正在检查…"
        case .current: "当前已是最新版本"
        case .available: "发现新版本"
        case .failed: "检查失败"
        }
    }
}
