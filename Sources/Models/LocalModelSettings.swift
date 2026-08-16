import Foundation

enum FunASRModel: String, CaseIterable, Identifiable, Codable {
    case sensevoiceSmallQ8 = "sensevoice-small-q8"

    var id: String { rawValue }

    var displayName: String {
        "SenseVoice Small q8 (~254MB)"
    }

    var detail: String {
        "中日韩英多语本地识别；需同时下载 FSMN-VAD"
    }

    var fileName: String {
        "sensevoice-small-q8.gguf"
    }

    /// Hugging Face 仓库路径片段，用于拼接 resolve URL。
    var repository: String {
        "FunAudioLLM/SenseVoiceSmall-GGUF"
    }

    var sizeMB: Int { 254 }
}

enum FunASRModelStore {
    /// App 沙箱内目录（正式读写位置）。调试包若开启 sandbox，也会落到 Containers 下。
    static let directory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("SubForge/models/funasr")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    static let vadFileName = "fsmn-vad.gguf"
    static let vadRepository = "FunAudioLLM/fsmn-vad-GGUF"
    static let vadSizeMB = 2

    static func localPath(for model: FunASRModel) -> URL {
        directory.appendingPathComponent(model.fileName)
    }

    static var vadPath: URL {
        directory.appendingPathComponent(vadFileName)
    }

    /// 安装包内置模型目录（`Contents/Resources/funasr/`）。
    static var bundledResourceDirectory: URL {
        Bundle.main.resourceURL?.appendingPathComponent("funasr")
            ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/funasr")
    }

    /// FileAttributeKey.size 在运行时是 NSNumber，直接 `as? Int64` 会失败并误判为「未下载」。
    private static func fileSize(at url: URL) -> Int64 {
        guard let value = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] else {
            return 0
        }
        if let number = value as? NSNumber {
            return number.int64Value
        }
        if let int64 = value as? Int64 {
            return int64
        }
        if let uint64 = value as? UInt64 {
            return Int64(uint64)
        }
        if let int = value as? Int {
            return Int64(int)
        }
        return 0
    }

    static func isBundled(_ model: FunASRModel = .sensevoiceSmallQ8) -> Bool {
        let asr = bundledResourceDirectory.appendingPathComponent(model.fileName)
        let vad = bundledResourceDirectory.appendingPathComponent(vadFileName)
        return fileSize(at: asr) > 10_000_000 && fileSize(at: vad) > 50_000
    }

    /// 兼容：优先包内 Resources，再沙箱 Application Support、开发机路径。
    private static func candidateDirectories() -> [URL] {
        var dirs: [URL] = [
            bundledResourceDirectory,
            directory
        ]
        let home = FileManager.default.homeDirectoryForCurrentUser
        dirs.append(
            home
                .appendingPathComponent("Library/Application Support/SubForge/models/funasr")
        )
        dirs.append(
            Bundle.main.bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("vendor/funasr")
        )
        var seen = Set<String>()
        return dirs.filter { url in
            let path = url.standardizedFileURL.path
            if seen.contains(path) { return false }
            seen.insert(path)
            return true
        }
    }

    static func existingPath(for fileName: String, minimumBytes: Int64) -> URL? {
        for dir in candidateDirectories() {
            let url = dir.appendingPathComponent(fileName)
            if fileSize(at: url) > minimumBytes {
                return url
            }
        }
        return nil
    }

    static func resolveModelPath(_ model: FunASRModel = .sensevoiceSmallQ8) -> URL? {
        if let found = existingPath(for: model.fileName, minimumBytes: 10_000_000) {
            // 包内 Resources 可直接读，不必先拷 242MB 进沙箱（VM 磁盘/内存紧时会拖很久）。
            if found.standardizedFileURL.path.hasPrefix(bundledResourceDirectory.standardizedFileURL.path) {
                return found
            }
            // 若找到沙箱外文件，尽量同步进沙箱目录，避免下次仍“未下载”
            let sandboxURL = localPath(for: model)
            if found.standardizedFileURL.path != sandboxURL.standardizedFileURL.path {
                try? FileManager.default.createDirectory(
                    at: sandboxURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if !FileManager.default.fileExists(atPath: sandboxURL.path) {
                    try? FileManager.default.copyItem(at: found, to: sandboxURL)
                }
                if FileManager.default.fileExists(atPath: sandboxURL.path) {
                    return sandboxURL
                }
            }
            return found
        }
        return nil
    }

    static func resolveVADPath() -> URL? {
        if let found = existingPath(for: vadFileName, minimumBytes: 50_000) {
            if found.standardizedFileURL.path.hasPrefix(bundledResourceDirectory.standardizedFileURL.path) {
                return found
            }
            let sandboxURL = vadPath
            if found.standardizedFileURL.path != sandboxURL.standardizedFileURL.path {
                try? FileManager.default.createDirectory(
                    at: sandboxURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if !FileManager.default.fileExists(atPath: sandboxURL.path) {
                    try? FileManager.default.copyItem(at: found, to: sandboxURL)
                }
                if FileManager.default.fileExists(atPath: sandboxURL.path) {
                    return sandboxURL
                }
            }
            return found
        }
        return nil
    }

    static func isModelAvailable(_ model: FunASRModel = .sensevoiceSmallQ8) -> Bool {
        resolveModelPath(model) != nil
    }

    static var isVADAvailable: Bool {
        resolveVADPath() != nil
    }

    static func isReady(_ model: FunASRModel = .sensevoiceSmallQ8) -> Bool {
        isModelAvailable(model) && isVADAvailable
    }
}
