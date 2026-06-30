import Foundation

final class WatchFolderService {
    private struct FileSnapshot: Equatable {
        let modificationDate: Date
        let fileSize: Int64
    }

    private let scanInterval: TimeInterval = 0.5
    private(set) var isWatching = false
    private(set) var statusMessage = "未启动"
    private(set) var processedCount = 0

    var onDetectedFCPAudio: ((URL) -> Bool)?
    var onStateChange: (() -> Void)?

    private var timer: Timer?
    private var watchedURL: URL?
    private var watchStartedAt: Date?
    private var processedSnapshots: [String: FileSnapshot] = [:]
    private var seenSnapshots: [String: FileSnapshot] = [:]

    func start(watching directory: URL) {
        if isWatching, watchedURL?.standardizedFileURL == directory.standardizedFileURL {
            return
        }

        stop()

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            statusMessage = "监听目录不存在"
            AppLog.watcher.error("watch start failed, directory missing: \(directory.path, privacy: .public)")
            notifyStateChange()
            return
        }

        watchedURL = directory
        watchStartedAt = Date()
        processedSnapshots = [:]
        seenSnapshots = [:]

        let scheduledTimer = Timer.scheduledTimer(withTimeInterval: scanInterval, repeats: true) { [weak self] _ in
            self?.checkDirectory()
        }
        scheduledTimer.tolerance = 0.1
        timer = scheduledTimer

        isWatching = true
        statusMessage = "正在监听：\(directory.lastPathComponent)"
        AppLog.watcher.info("watch started directory=\(directory.path, privacy: .public) interval=\(self.scanInterval, privacy: .public)")
        notifyStateChange()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isWatching = false
        watchedURL = nil
        watchStartedAt = nil
        seenSnapshots = [:]
        statusMessage = "未启动"
        AppLog.watcher.info("watch stopped")
        notifyStateChange()
    }

    private func checkDirectory() {
        guard let directory = watchedURL else { return }

        for file in listAudioFiles(in: directory) {
            let key = file.path
            guard let snapshot = fileSnapshot(file) else {
                AppLog.watcher.warning("watch skipped unreadable file snapshot: \(file.path, privacy: .public)")
                continue
            }

            if let watchStartedAt, snapshot.modificationDate < watchStartedAt {
                continue
            }

            if processedSnapshots[key] == snapshot {
                continue
            }

            guard fileIsStable(key: key, snapshot: snapshot) else {
                AppLog.watcher.debug("watch waiting stable file=\(file.lastPathComponent, privacy: .public) size=\(snapshot.fileSize, privacy: .public)")
                continue
            }

            if isFromFinalCutPro(file) {
                AppLog.watcher.info("watch confirmed FCP metadata file=\(file.lastPathComponent, privacy: .public)")
            } else {
                AppLog.watcher.info("watch accepted audio without FCP metadata file=\(file.lastPathComponent, privacy: .public)")
            }

            AppLog.watcher.info("watch detected FCP audio file=\(file.path, privacy: .public) size=\(snapshot.fileSize, privacy: .public)")
            let accepted = onDetectedFCPAudio?(file) ?? false
            if accepted {
                processedSnapshots[key] = snapshot
                processedCount += 1
                statusMessage = "已发现：\(file.lastPathComponent)"
            } else {
                statusMessage = "等待处理：\(file.lastPathComponent)"
                seenSnapshots[key] = snapshot
            }
            notifyStateChange()
        }
    }

    private func fileIsStable(key: String, snapshot: FileSnapshot) -> Bool {
        guard let previousSnapshot = seenSnapshots[key] else {
            seenSnapshots[key] = snapshot
            return false
        }

        if previousSnapshot != snapshot {
            seenSnapshots[key] = snapshot
            return false
        }

        seenSnapshots.removeValue(forKey: key)
        return true
    }

    private func listAudioFiles(in directory: URL) -> [URL] {
        let audioExtensions: Set<String> = ["m4a", "mp3", "wav", "aac", "aif", "aiff", "mp4"]
        var result: [URL] = []

        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        for case let url as URL in enumerator {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

            if isDirectory, shouldSkipDirectory(url) {
                enumerator.skipDescendants()
                continue
            }

            if audioExtensions.contains(url.pathExtension.lowercased()) {
                result.append(url)
            }
        }

        return result
    }

    private func shouldSkipDirectory(_ url: URL) -> Bool {
        let skippedNames: Set<String> = [".git", "node_modules", ".Trash", "__Trash"]
        let skippedExtensions: Set<String> = ["fcpbundle", "screenstudio", "app", "photoslibrary", "imovielibrary"]

        return skippedNames.contains(url.lastPathComponent)
            || skippedExtensions.contains(url.pathExtension.lowercased())
    }

    private func isFromFinalCutPro(_ url: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdls")
        process.arguments = ["-name", "kMDItemAudioEncodingApplication", url.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            AppLog.watcher.error("mdls failed for \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.lowercased().contains("final cut pro")
    }

    private func fileSnapshot(_ url: URL) -> FileSnapshot? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let modificationDate = values.contentModificationDate
        else {
            return nil
        }

        return FileSnapshot(
            modificationDate: modificationDate,
            fileSize: Int64(values.fileSize ?? 0)
        )
    }

    private func notifyStateChange() {
        onStateChange?()
    }
}
