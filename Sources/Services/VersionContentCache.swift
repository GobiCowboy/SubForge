import CryptoKit
import Foundation

final class VersionContentCache {
    private let fileManager: FileManager
    private let directoryURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directoryURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SubForge", isDirectory: true)
            .appendingPathComponent("VersionContent", isDirectory: true)
    }

    func manifestData() -> Data? {
        data(named: "manifest.json")
    }

    func manifestETag() -> String? {
        guard let data = data(named: "manifest.etag") else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func saveManifest(_ data: Data, etag: String?) {
        save(data, named: "manifest.json")
        if let etag {
            save(Data(etag.utf8), named: "manifest.etag")
        }
    }

    func resourceData(kind: String, hash: String) -> Data? {
        data(named: "\(kind)-\(safeHash(hash)).json")
    }

    func saveResource(_ data: Data, kind: String, hash: String) {
        save(data, named: "\(kind)-\(safeHash(hash)).json")
    }

    func imageData(hash: String) -> Data? {
        data(named: "image-\(safeHash(hash)).data")
    }

    func saveImage(_ data: Data, hash: String) {
        save(data, named: "image-\(safeHash(hash)).data")
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func data(named name: String) -> Data? {
        try? Data(contentsOf: directoryURL.appendingPathComponent(name))
    }

    private func save(_ data: Data, named name: String) {
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try data.write(to: directoryURL.appendingPathComponent(name), options: .atomic)
        } catch {
            AppLog.updates.error(
                "versionContentCacheWriteFailed file=\(name, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func safeHash(_ hash: String) -> String {
        hash.replacingOccurrences(of: "sha256:", with: "")
            .filter { $0.isNumber || ($0 >= "a" && $0 <= "f") || ($0 >= "A" && $0 <= "F") }
    }
}
