import Foundation

struct ManifestResult {
    let manifest: VersionContentManifest
    let baseURL: URL
    let sourceTitle: String
}

struct ContentSnapshot {
    let currentHelp: VersionHelpDocument
    let currentRelease: VersionReleaseNote
    let releaseNotes: [VersionReleaseNote]
    let latestRelease: VersionReleaseNote
    let latestVersion: AppVersion
    let downloadURL: URL?
    let sourceTitle: String
}

enum VersionContentError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case invalidManifest
    case missingContent
    case invalidContentURL
    case invalidContent
}

extension Array {
    func asyncCompactMap<T>(_ transform: (Element) async -> T?) async -> [T] {
        var values: [T] = []
        for element in self {
            if let value = await transform(element) {
                values.append(value)
            }
        }
        return values
    }
}
