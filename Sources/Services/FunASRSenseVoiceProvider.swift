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
        guard let cliPath = FunASRRuntime.resolveCLIPath() else {
            throw TranscriptionError.funASRCLIUnavailable
        }
        guard FunASRModelStore.isModelAvailable(model) else {
            throw TranscriptionError.funASRModelUnavailable
        }
        guard FunASRModelStore.isVADAvailable else {
            throw TranscriptionError.funASRVADUnavailable
        }

        // CLI 无 --language；auto 识别中日韩英。language 仅记日志便于排查。
        AppLog.transcription.info(
            "funASR start languageHint=\(language, privacy: .public) model=\(self.model.rawValue, privacy: .public)"
        )

        let wavURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("subforge_funasr_\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: wavURL) }

        try await Task.detached(priority: .userInitiated) {
            try Self.convertToWAV(input: audioURL, output: wavURL)
        }.value

        let duration = try await Self.audioDuration(of: audioURL)
        let modelPath = FunASRModelStore.localPath(for: model).path
        let vadPath = FunASRModelStore.vadPath.path

        let stdout = try await Task.detached(priority: .userInitiated) {
            try Self.runCLI(
                cliPath: cliPath,
                modelPath: modelPath,
                vadPath: vadPath,
                audioPath: wavURL.path
            )
        }.value

        let rawSegments = FunASROutputParser.parse(stdout: stdout, audioDuration: duration)
        let parsed = TimedSubtitleSegmenter.segmentEstimated(
            rawSegments,
            configuration: segmentationConfiguration
        )
        guard !parsed.isEmpty else {
            throw TranscriptionError.emptyResult
        }

        AppLog.transcription.info(
            "funASR done rawSegments=\(rawSegments.count, privacy: .public) outputSegments=\(parsed.count, privacy: .public) duration=\(duration, privacy: .public)"
        )
        return parsed
    }

    private static func convertToWAV(input: URL, output: URL) throws {
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

    private static func runCLI(
        cliPath: String,
        modelPath: String,
        vadPath: String,
        audioPath: String
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = [
            "-m", modelPath,
            "-a", audioPath,
            "--vad", vadPath
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            let detail = cleanError(stderr: stderr, stdout: stdout, status: process.terminationStatus)
            AppLog.transcription.error(
                "funASRCLI failed status=\(process.terminationStatus, privacy: .public) error=\(detail, privacy: .public)"
            )
            throw TranscriptionError.funASRExecutionFailed(detail)
        }

        if !stderr.isEmpty {
            AppLog.transcription.info("funASRCLI stderr=\(stderr.prefix(500), privacy: .public)")
        }

        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let detail = cleanError(stderr: stderr, stdout: stdout, status: process.terminationStatus)
            throw TranscriptionError.funASRExecutionFailed(
                detail.isEmpty ? "CLI 无文本输出" : detail
            )
        }
        return stdout
    }

    private static func cleanError(stderr: String, stdout: String, status: Int32) -> String {
        let lines = (stderr + "\n" + stdout)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !lines.isEmpty {
            return lines.prefix(8).joined(separator: "\n")
        }
        return "llama-funasr-sensevoice 执行失败（退出码 \(status)）"
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
