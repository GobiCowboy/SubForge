import Combine
import Foundation

@MainActor
final class VersionContentService: ObservableObject {
    @Published private(set) var currentHelp = VersionContentBuiltIn.help
    @Published private(set) var currentRelease = VersionContentBuiltIn.release
    @Published private(set) var releaseNotes: [VersionReleaseNote] = [VersionContentBuiltIn.release]
    @Published private(set) var latestRelease = VersionContentBuiltIn.release
    @Published private(set) var latestVersion = VersionContentRuntime.appVersion
    @Published private(set) var downloadURL: URL?
    @Published private(set) var state: VersionContentState = .idle
    @Published private(set) var sourceTitle = "内置帮助"
    @Published var pendingUpdate: VersionUpdateNotice?

    private let cache = VersionContentCache()
    private let decoder = JSONDecoder()
    private var didStart = false

    func start() {
        guard !didStart else { return }
        didStart = true
        Task { [weak self] in
            await self?.performCheck(isStartup: true)
        }
    }

    func checkForUpdates() {
        Task { [weak self] in
            await self?.performCheck(isStartup: false)
        }
    }

    func dismissPendingUpdate() {
        guard let pendingUpdate else { return }
        UserDefaults.standard.set(pendingUpdate.latestVersion, forKey: Self.lastSeenAvailableVersionKey)
        self.pendingUpdate = nil
    }

    private func performCheck(isStartup: Bool) async {
        state = .checking

        do {
            let manifestResult = try await loadManifest()
            let snapshot = try await assembleSnapshot(
                manifest: manifestResult.manifest,
                baseURL: manifestResult.baseURL,
                sourceTitle: manifestResult.sourceTitle
            )
            apply(snapshot)

            let currentVersion = VersionContentRuntime.appVersion
            if latestVersion > currentVersion {
                state = .available
                if isStartup, UserDefaults.standard.string(forKey: Self.lastSeenAvailableVersionKey) != latestVersion.description {
                    pendingUpdate = VersionUpdateNotice(
                        latestVersion: latestVersion.description,
                        title: latestRelease.title,
                        highlights: latestRelease.highlights
                    )
                }
            } else {
                state = .current
                pendingUpdate = nil
            }
        } catch {
            state = .failed("暂时无法获取版本内容，已使用本地帮助")
            AppLog.updates.error(
                "versionContentCheckFailed error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func apply(_ snapshot: ContentSnapshot) {
        currentHelp = snapshot.currentHelp
        currentRelease = snapshot.currentRelease
        releaseNotes = snapshot.releaseNotes
        latestRelease = snapshot.latestRelease
        latestVersion = snapshot.latestVersion
        downloadURL = snapshot.downloadURL
        sourceTitle = snapshot.sourceTitle
    }

    private func loadManifest() async throws -> ManifestResult {
        let cachedManifest = cachedManifest()
        var request = URLRequest(url: VersionContentRuntime.manifestURL)
        request.timeoutInterval = 6
        request.setValue("SubForge/\(VersionContentRuntime.appVersion)", forHTTPHeaderField: "User-Agent")
        if let etag = cache.manifestETag() {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw VersionContentError.invalidResponse
            }

            if httpResponse.statusCode == 304, let cachedManifest {
                return ManifestResult(
                    manifest: cachedManifest,
                    baseURL: VersionContentRuntime.manifestURL,
                    sourceTitle: "本地缓存"
                )
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                throw VersionContentError.httpStatus(httpResponse.statusCode)
            }

            let manifest = try validateManifest(try decoder.decode(VersionContentManifest.self, from: data))
            cache.saveManifest(data, etag: httpResponse.value(forHTTPHeaderField: "ETag"))
            return ManifestResult(
                manifest: manifest,
                baseURL: VersionContentRuntime.manifestURL,
                sourceTitle: "在线内容"
            )
        } catch {
            if let cachedManifest {
                return ManifestResult(
                    manifest: cachedManifest,
                    baseURL: VersionContentRuntime.manifestURL,
                    sourceTitle: "本地缓存"
                )
            }
            throw error
        }
    }

    private func cachedManifest() -> VersionContentManifest? {
        guard let data = cache.manifestData(),
              let manifest = try? decoder.decode(VersionContentManifest.self, from: data) else {
            return nil
        }
        return try? validateManifest(manifest)
    }

    private func validateManifest(_ manifest: VersionContentManifest) throws -> VersionContentManifest {
        guard manifest.schemaVersion == 1,
              manifest.appID == VersionContentRuntime.appID,
              AppVersion(manifest.latestVersion) != nil,
              !manifest.releases.isEmpty else {
            throw VersionContentError.invalidManifest
        }

        guard manifest.releases.allSatisfy({
            AppVersion($0.version) != nil &&
            AppVersion($0.helpVersion) != nil &&
            ($0.releaseSHA256?.hasPrefix("sha256:") == true) &&
            ($0.helpSHA256?.hasPrefix("sha256:") == true)
        }) else {
            throw VersionContentError.invalidManifest
        }
        return manifest
    }

    private func assembleSnapshot(
        manifest: VersionContentManifest,
        baseURL: URL,
        sourceTitle: String
    ) async throws -> ContentSnapshot {
        let currentVersion = VersionContentRuntime.appVersion
        let channel = manifest.channels[VersionContentRuntime.distributionChannel.rawValue]
        let resolvedLatestVersion = AppVersion(channel?.latestVersion ?? manifest.latestVersion) ?? currentVersion
        let sortedIndexes = manifest.releases.compactMap { index -> (AppVersion, VersionReleaseIndex)? in
            guard let version = AppVersion(index.version) else { return nil }
            return (version, index)
        }.sorted { $0.0 < $1.0 }

        let currentIndex = sortedIndexes.last(where: { $0.0 <= currentVersion })?.1
        let currentRelease = try await loadRelease(
            index: currentIndex,
            baseURL: baseURL,
            fallback: VersionContentBuiltIn.release
        )
        let currentHelp = try await loadHelp(
            index: currentIndex,
            baseURL: baseURL,
            fallback: VersionContentBuiltIn.help
        )

        let updateIndexes = sortedIndexes
            .filter { $0.0 > currentVersion && $0.0 <= resolvedLatestVersion }
            .map(\.1)
        let updates = await updateIndexes.asyncCompactMap { index in
            try? await loadRelease(index: index, baseURL: baseURL, fallback: nil)
        }
        let latestRelease = updates.last ?? currentRelease
        let allNotes = ([currentRelease] + updates).reduce(into: [String: VersionReleaseNote]()) { result, note in
            result[note.version] = note
        }

        return ContentSnapshot(
            currentHelp: currentHelp,
            currentRelease: currentRelease,
            releaseNotes: allNotes.values.sorted { (AppVersion($0.version) ?? currentVersion) < (AppVersion($1.version) ?? currentVersion) },
            latestRelease: latestRelease,
            latestVersion: resolvedLatestVersion,
            downloadURL: validHTTPSURL(channel?.downloadURL ?? manifest.storeURL),
            sourceTitle: sourceTitle
        )
    }

    private func loadRelease(
        index: VersionReleaseIndex?,
        baseURL: URL,
        fallback: VersionReleaseNote?
    ) async throws -> VersionReleaseNote {
        guard let index else {
            if let fallback { return fallback }
            throw VersionContentError.missingContent
        }
        return try await loadResource(
            kind: "release",
            urlString: index.releaseURL,
            expectedHash: index.releaseSHA256,
            baseURL: baseURL,
            fallback: fallback
        )
    }

    private func loadHelp(
        index: VersionReleaseIndex?,
        baseURL: URL,
        fallback: VersionHelpDocument
    ) async throws -> VersionHelpDocument {
        guard let index else { return fallback }
        return try await loadResource(
            kind: "help",
            urlString: index.helpURL,
            expectedHash: index.helpSHA256,
            baseURL: baseURL,
            fallback: fallback
        )
    }

    private func loadResource<T: Decodable>(
        kind: String,
        urlString: String,
        expectedHash: String?,
        baseURL: URL,
        fallback: T?
    ) async throws -> T {
        guard let expectedHash,
              let expectedHex = expectedHash.split(separator: ":").last,
              let url = URL(string: urlString, relativeTo: baseURL)?.absoluteURL,
              url.scheme == "https" else {
            if let fallback { return fallback }
            throw VersionContentError.invalidContentURL
        }

        if let cached = cache.resourceData(kind: kind, hash: expectedHash),
           VersionContentCache.sha256(cached) == expectedHex,
           let value = try? decoder.decode(T.self, from: cached) {
            return value
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        request.setValue("SubForge/\(VersionContentRuntime.appVersion)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  VersionContentCache.sha256(data) == expectedHex else {
                throw VersionContentError.invalidContent
            }
            let value = try decoder.decode(T.self, from: data)
            cache.saveResource(data, kind: kind, hash: expectedHash)
            return value
        } catch {
            if let fallback { return fallback }
            throw error
        }
    }

    private func validHTTPSURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), url.scheme == "https" else { return nil }
        return url
    }

    private static let lastSeenAvailableVersionKey = "subforge.lastSeenAvailableVersion"
}
