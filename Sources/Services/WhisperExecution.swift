import AVFoundation
import Foundation
import Speech

extension WhisperCppProvider {
    static func runWhisperCLI(
        cliPath: String,
        modelPath: String,
        wavURL: URL,
        language: String,
        dtwPreset: String
    ) throws -> WhisperTranscriptionResult {
        do {
            let result = try executeWhisperCLI(
                cliPath: cliPath,
                modelPath: modelPath,
                wavURL: wavURL,
                language: language,
                dtwPreset: dtwPreset,
                disableGPU: false
            )
            AppLog.transcription.info(
                "whisperCLI wordTimestamps=true dtwAligned=\(result.dtwAligned, privacy: .public) gpuRequested=true metalAvailable=\(result.metalAvailable, privacy: .public)"
            )
            return result
        } catch {
            AppLog.transcription.warning(
                "whisperCLI GPU path failed; retrying on CPU error=\(error.localizedDescription, privacy: .public)"
            )
            let result = try executeWhisperCLI(
                cliPath: cliPath,
                modelPath: modelPath,
                wavURL: wavURL,
                language: language,
                dtwPreset: dtwPreset,
                disableGPU: true
            )
            AppLog.transcription.info("whisperCLI wordTimestamps=true gpuRequested=false cpuFallback=true")
            return result
        }
    }

    static func executeWhisperCLI(
        cliPath: String,
        modelPath: String,
        wavURL: URL,
        language: String,
        dtwPreset: String,
        disableGPU: Bool
    ) throws -> WhisperTranscriptionResult {
        let outputBaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("subforge_whisper_words_\(UUID().uuidString)")
        let jsonURL = outputBaseURL.appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: jsonURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = [
            "-m", modelPath,
            "-f", wavURL.path,
            "-l", language.hasPrefix("zh") ? "zh" : language,
            "-t", "4",
            "--no-prints",
            "--dtw", dtwPreset,
            "--no-flash-attn",
            "--output-json-full",
            "--output-file", outputBaseURL.path
        ]
        if disableGPU {
            process.arguments?.append("--no-gpu")
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.environment = whisperEnvironment(for: cliPath)
        try process.run()
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let outputPreview = output
                .components(separatedBy: .newlines)
                .prefix(8)
                .joined(separator: "\n")
            let cleanedError = cleanWhisperError(
                error,
                output: outputPreview,
                terminationStatus: process.terminationStatus,
                terminationReason: process.terminationReason
            )
            AppLog.transcription.error(
                "whisperCLI failed status=\(process.terminationStatus, privacy: .public) reason=\(process.terminationReason.rawValue, privacy: .public) error=\(cleanedError, privacy: .public)"
            )
            throw TranscriptionError.whisperExecutionFailed(cleanedError)
        }

        do {
            let jsonData = try Data(contentsOf: jsonURL)
            return try WhisperJSONParser.parse(jsonData)
        } catch {
            AppLog.transcription.error(
                "whisperCLI word timestamp JSON invalid error=\(error.localizedDescription, privacy: .public)"
            )
            let fallbackSegments = parseWhisperOutput(output)
            guard !fallbackSegments.isEmpty else { throw error }
            return WhisperTranscriptionResult(
                segments: fallbackSegments,
                metalAvailable: false,
                dtwAligned: false
            )
        }
    }

    static func whisperEnvironment(for cliPath: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let cliURL = URL(fileURLWithPath: cliPath)
        let frameworkDirectory = cliURL.deletingLastPathComponent()

        let backendURL = frameworkDirectory.appendingPathComponent("libggml-blas.so")
        if FileManager.default.fileExists(atPath: backendURL.path) {
            environment["GGML_BACKEND_PATH"] = backendURL.path
        }
        environment["GGML_BACKTRACE_LLDB"] = "0"

        return environment
    }

    static func cleanWhisperError(
        _ error: String,
        output: String,
        terminationStatus: Int32,
        terminationReason: Process.TerminationReason
    ) -> String {
        let meaningfulLines = error
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                !line.isEmpty
                    && !line.hasPrefix("WARNING: Using native backtrace")
                    && !line.hasPrefix("WARNING: GGML_BACKTRACE_LLDB")
            }

        if !meaningfulLines.isEmpty {
            return meaningfulLines.joined(separator: "\n")
        }

        let outputLines = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !outputLines.isEmpty {
            return outputLines.joined(separator: "\n")
        }

        if terminationReason == .uncaughtSignal {
            return "whisper-cli 被运行库中断（信号 \(terminationStatus)）。已禁用 GPU 路径，请重新验证；如果仍出现，请把日志里的 whisperCLI failed 发给我。"
        }

        if terminationStatus == 133 || terminationStatus == 137 {
            return "whisper-cli 被系统终止，请确认应用内置的 Whisper 运行库完整。"
        }

        return "whisper-cli 执行失败（退出码 \(terminationStatus)）"
    }
}
