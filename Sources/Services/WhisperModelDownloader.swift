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

    static func download(
        _ model: WhisperModel,
        progress: @escaping @Sendable (Double?) -> Void = { _ in }
    ) async throws {
        let destination = WhisperModelStore.localPath(for: model)
        let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(model.fileName)

        for mirror in mirrors {
            do {
                progress(0)
                try await downloadViaURLSession(from: mirror + model.fileName, to: temporaryURL, progress: progress)

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
                progress(1)
                return
            } catch {
                try? FileManager.default.removeItem(at: temporaryURL)
                progress(nil)
            }
        }

        throw WhisperDownloadError.allMirrorsFailed
    }

    private static func downloadViaURLSession(
        from remoteURL: String,
        to localURL: URL,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws {
        guard let url = URL(string: remoteURL) else {
            throw WhisperDownloadError.downloadFailed(remoteURL)
        }

        let delegate = WhisperDownloadDelegate(destination: localURL, progress: progress)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        try await delegate.start(url: url, session: session)
    }
}

private final class WhisperDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    private let destination: URL
    private let progress: @Sendable (Double?) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var completionError: Error?
    private var didResume = false

    init(destination: URL, progress: @escaping @Sendable (Double?) -> Void) {
        self.destination = destination
        self.progress = progress
    }

    func start(url: URL, session: URLSession) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else {
            progress(nil)
            return
        }

        let fraction = min(max(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 0), 1)
        progress(fraction)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            completionError = error
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        lock.lock()
        defer { lock.unlock() }

        guard !didResume, let continuation else { return }
        didResume = true

        if let error {
            continuation.resume(throwing: error)
        } else if let completionError {
            continuation.resume(throwing: completionError)
        } else {
            continuation.resume()
        }
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
