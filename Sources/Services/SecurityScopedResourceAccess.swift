import Foundation

final class SecurityScopedResourceAccess {
    let url: URL
    private let isAccessing: Bool

    init(url: URL) {
        self.url = url
        self.isAccessing = url.startAccessingSecurityScopedResource()
    }

    init?(bookmarkData: Data?, fallbackPath: String, isDirectory: Bool) {
        if let bookmarkData,
           let resolvedURL = Self.resolve(bookmarkData: bookmarkData) {
            self.url = resolvedURL
        } else {
            let path = fallbackPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { return nil }
            self.url = URL(fileURLWithPath: path, isDirectory: isDirectory)
        }

        self.isAccessing = url.startAccessingSecurityScopedResource()
    }

    deinit {
        if isAccessing {
            url.stopAccessingSecurityScopedResource()
        }
    }

    static func bookmarkData(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private static func resolve(bookmarkData: Data) -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        return url
    }
}
