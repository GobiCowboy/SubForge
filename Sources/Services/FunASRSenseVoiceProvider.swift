import AVFoundation
import CoreMedia
import Foundation

extension Notification.Name {
    /// FunASR CLI 仍在运行时的心跳（userInfo: elapsed / duration，单位秒）。
    static let funASRTranscriptionHeartbeat = Notification.Name("com.jago.subforge.funASRTranscriptionHeartbeat")
}

/// 全局限流：同一时刻最多一个 FunASR 任务。
/// 进程拉起方式对齐 Whisper：`Process` + Frameworks 工作目录 + 环境变量，在 `Task.detached` 里同步 wait。
actor FunASRCLIRunner {
    static let shared = FunASRCLIRunner()

    private var activeProcess: Process?
    private var isRunningJob = false
    private var runGeneration: UInt64 = 0

    func run(
        cliPath: String,
        arguments: [String],
        timeoutSeconds: TimeInterval = 600,
        onElapsed: (@Sendable (TimeInterval) -> Void)? = nil
    ) async throws -> (stdout: String, stderr: String) {
        // 只杀「我们登记过的」进程，不再 pkill（沙箱里 pkill 不可靠，还会误伤新任务）
        await killActiveProcessOnly()
        try Task.checkCancellation()

        guard !isRunningJob else {
            throw TranscriptionError.funASRExecutionFailed("已有 FunASR 任务在运行，请稍后再试")
        }
        isRunningJob = true
        runGeneration &+= 1
        let generation = runGeneration
        defer {
            if runGeneration == generation {
                isRunningJob = false
                activeProcess = nil
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = arguments
        // 与 Whisper 一致：在 Frameworks 目录下跑，便于加载同目录后端
        let frameworksURL = URL(fileURLWithPath: cliPath).deletingLastPathComponent()
        process.currentDirectoryURL = frameworksURL
        process.environment = Self.funASREnvironment(frameworksDirectory: frameworksURL)

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        activeProcess = process

        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) { () -> (String, String) in
                try process.run()
                let pid = process.processIdentifier
                let startedAt = Date()

                // 边跑边读，避免 pipe 塞满（Whisper 用 --no-prints，FunASR 仍可能打日志）
                let stdoutHandle = outputPipe.fileHandleForReading
                let stderrHandle = errorPipe.fileHandleForReading
                let stdoutBox = FunASRDataBox()
                let stderrBox = FunASRDataBox()
                let readGroup = DispatchGroup()

                readGroup.enter()
                DispatchQueue.global(qos: .utility).async {
                    stdoutBox.append(stdoutHandle.readDataToEndOfFile())
                    readGroup.leave()
                }
                readGroup.enter()
                DispatchQueue.global(qos: .utility).async {
                    stderrBox.append(stderrHandle.readDataToEndOfFile())
                    readGroup.leave()
                }

                let timeout = timeoutSeconds
                let watchdog = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
                watchdog.schedule(deadline: .now() + timeout, repeating: .never)
                watchdog.setEventHandler {
                    if process.isRunning {
                        AppLog.transcription.error(
                            "funASRCLI timeout seconds=\(timeout, privacy: .public) pid=\(pid, privacy: .public)"
                        )
                        process.terminate()
                        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                            if process.isRunning { kill(pid, SIGKILL) }
                        }
                    }
                }
                watchdog.resume()

                var heartbeat: DispatchSourceTimer?
                if let onElapsed {
                    let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
                    timer.schedule(deadline: .now() + 2, repeating: 2)
                    timer.setEventHandler {
                        guard process.isRunning else { return }
                        onElapsed(Date().timeIntervalSince(startedAt))
                    }
                    timer.resume()
                    heartbeat = timer
                }

                process.waitUntilExit()
                watchdog.cancel()
                heartbeat?.cancel()
                // 等读线程收完
                _ = readGroup.wait(timeout: .now() + 5)

                let stdout = String(data: stdoutBox.data(), encoding: .utf8) ?? ""
                let stderr = String(data: stderrBox.data(), encoding: .utf8) ?? ""

                AppLog.transcription.info(
                    "funASRCLI exit status=\(process.terminationStatus, privacy: .public) reason=\(process.terminationReason.rawValue, privacy: .public) stdoutBytes=\(stdout.utf8.count, privacy: .public) stderrBytes=\(stderr.utf8.count, privacy: .public)"
                )

                if process.terminationReason == .uncaughtSignal
                    || process.terminationStatus == 15
                    || process.terminationStatus == 9
                    || process.terminationStatus == 5
                    || process.terminationStatus == 133 {
                    let status = process.terminationStatus
                    if status == 5 || status == 133 {
                        throw TranscriptionError.funASRExecutionFailed(
                            "FunASR 运行时被系统拦截（信号 \(status)）。多为嵌套 CLI 签名/隔离属性问题。请重新安装或对 app 内 llama-funasr-sensevoice 做 codesign。"
                        )
                    }
                    if stderr.isEmpty && stdout.isEmpty {
                        throw TranscriptionError.funASRExecutionFailed("转写超时或被中断，请重试（勿连续多次点击）")
                    }
                    throw CancellationError()
                }

                if process.terminationStatus != 0 {
                    let detail = FunASRSenseVoiceProvider.cleanError(
                        stderr: stderr,
                        stdout: stdout,
                        status: process.terminationStatus
                    )
                    throw TranscriptionError.funASRExecutionFailed(detail)
                }

                return (stdout, stderr)
            }.value
        } onCancel: {
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) {
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
        }
    }

    func cancelActive() async {
        await killActiveProcessOnly()
    }

    private func killActiveProcessOnly() async {
        if let process = activeProcess, process.isRunning {
            let pid = process.processIdentifier
            process.terminate()
            try? await Task.sleep(nanoseconds: 300_000_000)
            if process.isRunning {
                kill(pid, SIGKILL)
            }
        }
        activeProcess = nil
        isRunningJob = false
    }

    /// 对齐 Whisper 的 `whisperEnvironment`：给 ggml 指到 Frameworks。
    nonisolated static func funASREnvironment(frameworksDirectory: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["GGML_BACKEND_PATH"] = frameworksDirectory.path
        environment["GGML_BACKTRACE_LLDB"] = "0"
        // 部分构建会扫 cwd / 库路径找 backend
        let existing = environment["DYLD_LIBRARY_PATH"] ?? ""
        if existing.isEmpty {
            environment["DYLD_LIBRARY_PATH"] = frameworksDirectory.path
        } else if !existing.contains(frameworksDirectory.path) {
            environment["DYLD_LIBRARY_PATH"] = frameworksDirectory.path + ":" + existing
        }
        return environment
    }
}

private final class FunASRDataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        storage.append(data)
        lock.unlock()
    }

    func data() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

final class FunASRSenseVoiceProvider: TranscriptionProvider {
    private let model: FunASRModel
    private let segmentationConfiguration: SubtitleSegmentationConfiguration

    init(
        model: FunASRModel = .sensevoiceSmallQ8,
        segmentationConfiguration: SubtitleSegmentationConfiguration
    ) {
        self.model = model
        self.segmentationConfiguration = segmentationConfiguration
    }

    func transcribe(audioURL: URL, language: String) async throws -> [SubtitleSegment] {
        guard let asrCLI = FunASRRuntime.resolveCLIPath() else {
            throw TranscriptionError.funASRCLIUnavailable
        }
        guard let modelURL = FunASRModelStore.resolveModelPath(model) else {
            throw TranscriptionError.funASRModelUnavailable
        }
        guard let vadModelURL = FunASRModelStore.resolveVADPath() else {
            throw TranscriptionError.funASRVADUnavailable
        }

        AppLog.transcription.info(
            "funASR start languageHint=\(language, privacy: .public) model=\(self.model.rawValue, privacy: .public) modelPath=\(modelURL.path, privacy: .public) cli=\(asrCLI, privacy: .public)"
        )

        try Task.checkCancellation()

        // 外部音频先进沙箱（与 Whisper 同一套 SandboxMediaAccess）
        let prepared = try SandboxMediaAccess.prepareForProcessing(audioURL)
        defer { prepared.cleanup() }

        // 与 Whisper 一致：只把音频落到 temp wav；模型仍用已解析路径（包内/沙箱 AS，不每轮拷 242MB）
        let wavURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("subforge_funasr_\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: wavURL) }

        AppLog.transcription.info(
            "funASR convert start source=\(prepared.url.lastPathComponent, privacy: .public) tempCopy=\(prepared.isTemporaryCopy, privacy: .public)"
        )

        try await Task.detached(priority: .userInitiated) {
            try Self.convertToWAV(input: prepared.url, output: wavURL)
        }.value

        guard FileManager.default.fileExists(atPath: wavURL.path) else {
            throw TranscriptionError.audioConversionFailed
        }

        try Task.checkCancellation()

        let duration = try await Self.audioDuration(of: prepared.url)
        let timeoutSeconds = min(3600, max(180, duration * 8 + 120))

        AppLog.transcription.info(
            "funASR CLI launch duration=\(duration, privacy: .public)s timeout=\(timeoutSeconds, privacy: .public)s model=\(modelURL.lastPathComponent, privacy: .public)"
        )

        // 只跑一次 SenseVoice（内置 --vad），进程模型对齐 Whisper 的单次 Process
        let asrResult = try await FunASRCLIRunner.shared.run(
            cliPath: asrCLI,
            arguments: [
                "-m", modelURL.path,
                "-a", wavURL.path,
                "--vad", vadModelURL.path
            ],
            timeoutSeconds: timeoutSeconds,
            onElapsed: { elapsed in
                AppLog.transcription.info(
                    "funASRCLI running elapsed=\(elapsed, privacy: .public)s audioDuration=\(duration, privacy: .public)s"
                )
                NotificationCenter.default.post(
                    name: .funASRTranscriptionHeartbeat,
                    object: nil,
                    userInfo: [
                        "elapsed": elapsed,
                        "duration": duration
                    ]
                )
            }
        )
        if !asrResult.stderr.isEmpty {
            AppLog.transcription.info(
                "funASRCLI stderr=\(asrResult.stderr.prefix(500), privacy: .public)"
            )
        }

        try Task.checkCancellation()

        let text = FunASROutputParser.plainText(from: asrResult.stdout)
        guard !text.isEmpty else {
            let hint = asrResult.stderr.isEmpty ? "CLI 无文本输出" : String(asrResult.stderr.prefix(200))
            AppLog.transcription.error("funASR empty text stderr=\(hint, privacy: .public)")
            throw TranscriptionError.emptyResult
        }

        let coarse = [
            SubtitleSegment(start: 0, end: max(duration, 0.5), text: text)
        ]
        let parsed = TimedSubtitleSegmenter.segmentEstimated(
            coarse,
            configuration: segmentationConfiguration
        )
        guard !parsed.isEmpty else {
            throw TranscriptionError.emptyResult
        }

        AppLog.transcription.info(
            "funASR done outputSegments=\(parsed.count, privacy: .public) duration=\(duration, privacy: .public)"
        )
        return parsed
    }

    private static func convertToWAV(input: URL, output: URL) throws {
        // 与 Whisper 相同的 afconvert 参数
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        process.arguments = [
            "-f", "WAVE",
            "-d", "LEI16@16000",
            "-c", "1",
            input.path,
            output.path
        ]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw TranscriptionError.audioConversionFailed
        }
    }

    static func cleanError(stderr: String, stdout: String, status: Int32) -> String {
        let lines = (stderr + "\n" + stdout)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !lines.isEmpty {
            return lines.prefix(8).joined(separator: "\n")
        }
        return "FunASR CLI 执行失败（退出码 \(status)）"
    }

    private static func audioDuration(of url: URL) async throws -> TimeInterval {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            return seconds.isNaN || seconds <= 0 ? 10.0 : seconds
        } catch {
            return 10.0
        }
    }
}
