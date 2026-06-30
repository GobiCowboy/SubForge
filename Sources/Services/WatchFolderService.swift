import Foundation

final class WatchFolderService {
    private(set) var isWatching = false
    private(set) var statusMessage = "未启动"
    private(set) var processedCount = 0

    var onDetectedFCPAudio: ((URL) -> Bool)?
    var onStateChange: (() -> Void)?

    private var timer: Timer?
    private var watchedURL: URL?
    private var processedTimestamps: [String: Date] = [:]
    private var seenTimestamps: [String: Date] = [:]

    func start(watching directory: URL) {
        if isWatching, watchedURL?.standardizedFileURL == directory.standardizedFileURL {
            return
        }

        stop()

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            statusMessage = "监听目录不存在"
            notifyStateChange()
            return
        }

        watchedURL = directory
        processedTimestamps = [:]
        seenTimestamps = [:]

        for file in listAudioFiles(in: directory) {
            if let date = modificationDate(file) {
                processedTimestamps[file.path] = date
            }
        }

        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.checkDirectory()
        }

        isWatching = true
        statusMessage = "正在监听：\(directory.lastPathComponent)"
        notifyStateChange()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isWatching = false
        watchedURL = nil
        seenTimestamps = [:]
        statusMessage = "未启动"
        notifyStateChange()
    }

    private func checkDirectory() {
        guard let directory = watchedURL else { return }

        for file in listAudioFiles(in: directory) {
            let key = file.path
            guard let modDate = modificationDate(file) else { continue }

            if let processedDate = processedTimestamps[key], modDate <= processedDate {
                continue
            }

            guard fileIsStable(file, key: key, modDate: modDate) else {
                continue
            }

            guard isFromFinalCutPro(file) else {
                processedTimestamps[key] = modDate
                continue
            }

            let accepted = onDetectedFCPAudio?(file) ?? false
            if accepted {
                processedTimestamps[key] = modDate
                processedCount += 1
                statusMessage = "已发现：\(file.lastPathComponent)"
            } else {
                statusMessage = "等待处理：\(file.lastPathComponent)"
                seenTimestamps[key] = modDate
            }
            notifyStateChange()
        }
    }

    private func fileIsStable(_ file: URL, key: String, modDate: Date) -> Bool {
        guard let firstSeenDate = seenTimestamps[key] else {
            seenTimestamps[key] = modDate
            return false
        }

        if firstSeenDate != modDate {
            seenTimestamps[key] = modDate
            return false
        }

        seenTimestamps.removeValue(forKey: key)
        return true
    }

    private func listAudioFiles(in directory: URL) -> [URL] {
        let audioExtensions: Set<String> = ["m4a", "mp3", "wav", "aac", "aif", "aiff", "mp4"]
        let skippedDirectories: Set<String> = [".fcpbundle", ".screenstudio", ".git", "node_modules", ".Trash"]
        var result: [URL] = []

        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        for case let url as URL in enumerator {
            if skippedDirectories.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }

            if audioExtensions.contains(url.pathExtension.lowercased()) {
                result.append(url)
            }
        }

        return result
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

    private func modificationDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func notifyStateChange() {
        onStateChange?()
    }
}
