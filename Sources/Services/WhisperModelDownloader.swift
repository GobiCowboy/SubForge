import Foundation

enum WhisperRuntime {
    static var cliCandidates: [String] {
        [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/whisper-cli").path,
            WhisperModelStore.directory.deletingLastPathComponent().appendingPathComponent("whisper-cli").path,
            "/opt/homebrew/opt/whisper-cpp/bin/whisper-cli",
            "/opt/homebrew/bin/whisper-cli"
        ]
    }

    static var isCLIAvailable: Bool {
        cliCandidates.contains { FileManager.default.fileExists(atPath: $0) }
    }
}

enum WhisperModelDownloader {
    private static let mirrors = [
        "https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main/",
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/"
    ]

    static func download(_ model: WhisperModel) async throws {
        let destination = WhisperModelStore.localPath(for: model)
        let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(model.fileName)

        for mirror in mirrors {
            do {
                try await downloadViaCurl(from: mirror + model.fileName, to: temporaryURL)

                let attributes = try FileManager.default.attributesOfItem(atPath: temporaryURL.path)
                let fileSize = attributes[.size] as? Int64 ?? 0
                guard fileSize > 1_000_000 else {
                    try? FileManager.default.removeItem(at: temporaryURL)
                    continue
                }

                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: temporaryURL, to: destination)
                return
            } catch {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
        }

        throw WhisperDownloadError.allMirrorsFailed
    }

    private static func downloadViaCurl(from remoteURL: String, to localURL: URL) async throws {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            process.arguments = [
                "-L",
                "--fail",
                "--connect-timeout", "15",
                "--max-time", "1800",
                "-o", localURL.path,
                remoteURL
            ]

            let errorPipe = Pipe()
            process.standardError = errorPipe
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                throw WhisperDownloadError.downloadFailed(message.isEmpty ? remoteURL : message)
            }
        }.value
    }
}

enum WhisperDownloadError: LocalizedError {
    case downloadFailed(String)
    case allMirrorsFailed

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let message):
            return "下载失败：\(message)"
        case .allMirrorsFailed:
            return "所有下载源都失败了，请检查网络或代理设置"
        }
    }
}
