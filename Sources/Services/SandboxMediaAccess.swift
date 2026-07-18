import Foundation

/// 把「用户选中的外部音频」变成沙箱内可读路径。
///
/// 设置页验证用 Bundle 测试音频；正式导入用外部文件。沙箱子进程读不了安全作用域路径，
/// 所以要把文件拷进 App 临时目录再交给 afconvert / FunASR / Whisper。
enum SandboxMediaAccess {
    struct PreparedFile {
        let url: URL
        /// 是否为拷贝出来的临时文件（用完需清理）
        let isTemporaryCopy: Bool

        func cleanup() {
            guard isTemporaryCopy else { return }
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// 返回可供 `afconvert` / FunASR / Whisper 子进程稳定读取的本地文件。
    static func prepareForProcessing(_ sourceURL: URL) throws -> PreparedFile {
        let source = sourceURL.standardizedFileURL

        // 嵌套 startAccessing：调用方（AppModel）可能已持有一层，这里再加一层更稳。
        let accessing = source.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                source.stopAccessingSecurityScopedResource()
            }
        }

        AppLog.transcription.info(
            "sandbox media prepare path=\(source.path, privacy: .public) accessing=\(accessing, privacy: .public) readable=\(FileManager.default.isReadableFile(atPath: source.path), privacy: .public)"
        )

        // 包内 / 已在沙箱 temp 的，直接用。
        if isAppBundleResource(source) || isInsideAppWritableArea(source) {
            guard FileManager.default.isReadableFile(atPath: source.path) else {
                throw TranscriptionError.audioSourceUnreadable
            }
            return PreparedFile(url: source, isTemporaryCopy: false)
        }

        let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("subforge_import_\(UUID().uuidString).\(ext)")
        if FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.removeItem(at: dest)
        }

        // 1) 优先 copyItem（流式拷贝，不把整文件读进内存；NSOpenPanel 授权后通常可用）
        do {
            try FileManager.default.copyItem(at: source, to: dest)
            let size = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? NSNumber)?.intValue ?? 0
            guard size > 0 else {
                try? FileManager.default.removeItem(at: dest)
                throw TranscriptionError.audioSourceUnreadable
            }
            AppLog.transcription.info(
                "sandbox media copyItem ok bytes=\(size, privacy: .public) from=\(source.lastPathComponent, privacy: .public)"
            )
            return PreparedFile(url: dest, isTemporaryCopy: true)
        } catch {
            AppLog.transcription.warning(
                "sandbox media copyItem failed error=\(error.localizedDescription, privacy: .public); try stream"
            )
        }

        // 2) FileHandle 流式读入再写（避免 mappedIfSafe 在部分卷上失败）
        do {
            let handle = try FileHandle(forReadingFrom: source)
            defer { try? handle.close() }
            let data = handle.readDataToEndOfFile()
            guard !data.isEmpty else {
                throw TranscriptionError.audioSourceUnreadable
            }
            try data.write(to: dest, options: .atomic)
            AppLog.transcription.info(
                "sandbox media stream ok bytes=\(data.count, privacy: .public) from=\(source.lastPathComponent, privacy: .public)"
            )
            return PreparedFile(url: dest, isTemporaryCopy: true)
        } catch {
            AppLog.transcription.warning(
                "sandbox media stream failed error=\(error.localizedDescription, privacy: .public)"
            )
        }

        // 3) 无沙箱 / 已授权可读：直接把原路径交给后续（afconvert 与主进程同权限时可用）
        if FileManager.default.isReadableFile(atPath: source.path) {
            AppLog.transcription.info(
                "sandbox media fallback use original path=\(source.lastPathComponent, privacy: .public)"
            )
            return PreparedFile(url: source, isTemporaryCopy: false)
        }

        AppLog.transcription.error(
            "sandbox media all strategies failed path=\(source.path, privacy: .public)"
        )
        throw TranscriptionError.audioSourceUnreadable
    }

    private static func isAppBundleResource(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        if let resourcePath = Bundle.main.resourcePath, path.hasPrefix(resourcePath) {
            return true
        }
        let bundlePath = Bundle.main.bundleURL.standardizedFileURL.path
        return path.hasPrefix(bundlePath)
    }

    private static func isInsideAppWritableArea(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let tmp = FileManager.default.temporaryDirectory.standardizedFileURL.path
        if path.hasPrefix(tmp) {
            return true
        }
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.path,
           path.hasPrefix(caches) {
            return true
        }
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.path,
           path.hasPrefix(support) {
            return true
        }
        return false
    }
}
