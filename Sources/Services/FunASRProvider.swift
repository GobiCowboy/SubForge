import AVFoundation
import CoreMedia
import Foundation

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
