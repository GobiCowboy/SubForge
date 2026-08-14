import Foundation

@MainActor
final class VersionContentImageStore {
    static let shared = VersionContentImageStore()

    private let cache = VersionContentCache()

    func load(urlString: String, sha256: String) async -> Data? {
        guard let expectedHex = expectedHash(from: sha256),
              let url = URL(string: urlString),
              VersionContentRuntime.isAllowedContentURL(url) else {
            return nil
        }

        if let cached = cache.imageData(hash: sha256),
           VersionContentCache.sha256(cached) == expectedHex {
            return cached
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("SubForge/\(VersionContentRuntime.appVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  VersionContentCache.sha256(data) == expectedHex else {
                return nil
            }

            cache.saveImage(data, hash: sha256)
            return data
        } catch {
            AppLog.updates.debug(
                "versionContentImageLoadFailed url=\(url.absoluteString, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    private func expectedHash(from value: String) -> String? {
        let parts = value.split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              parts[0].lowercased() == "sha256",
              parts[1].count == 64,
              parts[1].allSatisfy({ $0.isHexDigit }) else {
            return nil
        }

        return String(parts[1]).lowercased()
    }
}
