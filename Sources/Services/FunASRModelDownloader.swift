import Foundation

enum FunASRRuntime {
    static let cliFileName = "llama-funasr-sensevoice"

    static var cliCandidates: [String] {
        [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/\(cliFileName)").path,
            FunASRModelStore.directory
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("bin/\(cliFileName)").path,
            Bundle.main.bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("vendor/funasr/\(cliFileName)").path,
            FileManager.default.currentDirectoryPath + "/vendor/funasr/\(cliFileName)"
        ]
    }

    static var isCLIAvailable: Bool {
        cliCandidates.contains { FileManager.default.isExecutableFile(atPath: $0) || FileManager.default.fileExists(atPath: $0) }
    }

    static func resolveCLIPath() -> String? {
        cliCandidates.first {
            FileManager.default.isExecutableFile(atPath: $0) || FileManager.default.fileExists(atPath: $0)
        }
    }
}

enum FunASRModelDownloader {
    private static let mirrors = [
        "https://hf-mirror.com/",
        "https://huggingface.co/"
    ]

    static func download(
        _ model: FunASRModel = .sensevoiceSmallQ8,
        progress: @escaping @Sendable (Double?) -> Void = { _ in }
    ) async throws {
        try await downloadFile(
            repository: model.repository,
            fileName: model.fileName,
            destination: FunASRModelStore.localPath(for: model),
            minimumBytes: 10_000_000,
            progressRange: 0.0...0.88,
            progress: progress
        )

        try await downloadFile(
            repository: FunASRModelStore.vadRepository,
            fileName: FunASRModelStore.vadFileName,
            destination: FunASRModelStore.vadPath,
            minimumBytes: 50_000,
            progressRange: 0.88...1.0,
            progress: progress
        )

        progress(1)
    }

    private static func downloadFile(
        repository: String,
        fileName: String,
        destination: URL,
        minimumBytes: Int64,
        progressRange: ClosedRange<Double>,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("subforge_funasr_\(UUID().uuidString)_\(fileName)")

        for mirror in mirrors {
            let remote = "\(mirror)\(repository)/resolve/main/\(fileName)"
            do {
                progress(progressRange.lowerBound)
                try await downloadViaURLSession(from: remote, to: temporaryURL) { raw in
                    guard let raw else {
                        progress(nil)
                        return
                    }
                    let span = progressRange.upperBound - progressRange.lowerBound
                    progress(progressRange.lowerBound + raw * span)
                }

                let attributes = try FileManager.default.attributesOfItem(atPath: temporaryURL.path)
                let fileSize = attributes[.size] as? Int64 ?? 0
                guard fileSize > minimumBytes else {
                    try? FileManager.default.removeItem(at: temporaryURL)
                    continue
                }

                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: temporaryURL, to: destination)
                return
            } catch {
                try? FileManager.default.removeItem(at: temporaryURL)
                progress(nil)
            }
        }

        throw FunASRDownloadError.allMirrorsFailed(fileName)
    }

    private static func downloadViaURLSession(
        from remoteURL: String,
        to localURL: URL,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws {
        guard let url = URL(string: remoteURL) else {
            throw FunASRDownloadError.downloadFailed(remoteURL)
        }

        let delegate = FunASRDownloadDelegate(destination: localURL, progress: progress)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        try await delegate.start(url: url, session: session)
    }
}

enum FunASRDownloadError: LocalizedError {
    case allMirrorsFailed(String)
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .allMirrorsFailed(let fileName):
            "FunASR 模型下载失败：\(fileName)。请检查网络后重试。"
        case .downloadFailed(let remote):
            "无法下载：\(remote)"
        }
    }
}

private final class FunASRDownloadDelegate: NSObject, URLSessionDownloadDelegate {
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
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
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
        progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
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
            finish(nil)
        } catch {
            finish(error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(error)
        }
    }

    private func finish(_ error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return }
        didResume = true
        if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
        continuation = nil
    }
}
