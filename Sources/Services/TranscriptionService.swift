import AVFoundation
import Foundation
import Speech

protocol TranscriptionProvider {
    func transcribe(audioURL: URL, language: String) async throws -> [SubtitleSegment]
}

struct TranscriptionTestResult {
    let available: Bool
    let message: String
    let recognizedText: String?
}

final class AppleSpeechProvider: TranscriptionProvider {
    private let segmentationConfiguration: SubtitleSegmentationConfiguration

    init(segmentationConfiguration: SubtitleSegmentationConfiguration) {
        self.segmentationConfiguration = segmentationConfiguration
    }

    func transcribe(audioURL: URL, language: String) async throws -> [SubtitleSegment] {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard status == .authorized else {
            throw TranscriptionError.notAuthorized(status)
        }

        let locale = Locale(identifier: language)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable(language)
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.requiresOnDeviceRecognition = false
        request.addsPunctuation = true
        request.taskHint = .dictation

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            var latestSegments: [SubtitleSegment] = []

            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    guard !hasResumed else { return }
                    hasResumed = true
                    if latestSegments.isEmpty {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: latestSegments)
                    }
                    return
                }

                guard let result else { return }
                let appleSegments = result.bestTranscription.segments
                let timedWords = appleSegments.enumerated().map { index, segment in
                    let nextStart = appleSegments.indices.contains(index + 1)
                        ? appleSegments[index + 1].timestamp
                        : segment.timestamp + segment.duration
                    let end = Self.normalizedSegmentEnd(
                        start: segment.timestamp,
                        duration: segment.duration,
                        characterCount: segment.substring.count,
                        nextStart: nextStart
                    )
                    if segment.duration > 5.2 {
                        AppLog.transcription.warning(
                            "appleSpeech abnormalSegmentDuration raw=\(segment.duration, privacy: .public) clamped=\(end - segment.timestamp, privacy: .public) characterCount=\(segment.substring.count, privacy: .public)"
                        )
                    }
                    return SubtitleWord(
                        start: segment.timestamp,
                        end: max(end, segment.timestamp + 0.1),
                        text: segment.substring
                    )
                }
                latestSegments = TimedSubtitleSegmenter.segment(
                    timedWords,
                    configuration: self.segmentationConfiguration
                )

                if result.isFinal && !hasResumed {
                    let rawStart = timedWords.first?.start ?? 0
                    let rawEnd = timedWords.last?.end ?? 0
                    let outputStart = latestSegments.first?.start ?? 0
                    let outputEnd = latestSegments.last?.end ?? 0
                    AppLog.transcription.info(
                        "appleSpeech final rawSegments=\(timedWords.count, privacy: .public) rawRange=\(rawStart, privacy: .public)-\(rawEnd, privacy: .public) outputSegments=\(latestSegments.count, privacy: .public) outputRange=\(outputStart, privacy: .public)-\(outputEnd, privacy: .public) maxCharacters=\(self.segmentationConfiguration.maxCharacters, privacy: .public)"
                    )
                    hasResumed = true
                    continuation.resume(returning: latestSegments)
                }
            }

            Task {
                try? await Task.sleep(nanoseconds: 300_000_000_000)
                guard !hasResumed else { return }
                hasResumed = true
                task.cancel()
                if latestSegments.isEmpty {
                    continuation.resume(throwing: TranscriptionError.timeout)
                } else {
                    continuation.resume(returning: latestSegments)
                }
            }
        }
    }

    static func normalizedSegmentEnd(
        start: TimeInterval,
        duration: TimeInterval,
        characterCount: Int,
        nextStart: TimeInterval
    ) -> TimeInterval {
        let rawEnd = start + duration
        if duration > 5.2 {
            let readableDuration = max(1.2, min(3.0, Double(characterCount) * 0.45 + 0.6))
            return max(start + 0.1, min(min(rawEnd, start + readableDuration), nextStart))
        }
        return max(start + 0.1, min(rawEnd, max(nextStart, start + 0.1)))
    }

}

final class WhisperCppProvider: TranscriptionProvider {
    private let model: WhisperModel
    private let segmentationConfiguration: SubtitleSegmentationConfiguration

    init(model: WhisperModel, segmentationConfiguration: SubtitleSegmentationConfiguration) {
        self.model = model
        self.segmentationConfiguration = segmentationConfiguration
    }

    func transcribe(audioURL: URL, language: String) async throws -> [SubtitleSegment] {
        let cliPath = try resolveCLIPath()
        let modelPath = try resolveModelPath()
        let prepared = try SandboxMediaAccess.prepareForProcessing(audioURL)
        defer { prepared.cleanup() }

        let wavURL = FileManager.default.temporaryDirectory.appendingPathComponent("subforge_whisper_\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: wavURL) }

        try await Task.detached(priority: .userInitiated) {
            try Self.convertToWAV(input: prepared.url, output: wavURL)
        }.value

        let dtwPreset = model.rawValue

        let whisperResult = try await Task.detached(priority: .userInitiated) {
            try Self.runWhisperCLI(
                cliPath: cliPath,
                modelPath: modelPath,
                wavURL: wavURL,
                language: language,
                dtwPreset: dtwPreset
            )
        }.value

        let rawSegments = whisperResult.segments
        let timedWords = rawSegments.flatMap { $0.words ?? [] }
        let parsed = timedWords.isEmpty
            ? TimedSubtitleSegmenter.segmentEstimated(rawSegments, configuration: segmentationConfiguration)
            : TimedSubtitleSegmenter.segment(timedWords, configuration: segmentationConfiguration)
        guard !parsed.isEmpty else {
            throw TranscriptionError.emptyResult
        }
        return parsed
    }

    private func resolveCLIPath() throws -> String {
        if let path = WhisperRuntime.cliCandidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            return path
        }

        throw TranscriptionError.cliUnavailable
    }

    private func resolveModelPath() throws -> String {
        if let requestedPath = WhisperModelStore.existingPath(for: model)?.path {
            return requestedPath
        }

        if let availableModel = WhisperModelStore.availableModels().first {
            if let availablePath = WhisperModelStore.existingPath(for: availableModel)?.path {
                return availablePath
            }
        }

        throw TranscriptionError.modelUnavailable
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

    private static func leadingAudibleOffset(in wavURL: URL) throws -> TimeInterval {
        let file = try AVAudioFile(forReading: wavURL)
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        guard sampleRate > 0 else { return 0 }

        let windowFrames = max(1, Int(sampleRate * 0.08))
        let chunkSize: AVAudioFrameCount = 4096
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkSize) else {
            return 0
        }

        var windowEnergy: Double = 0
        var windowFrameCount = 0
        var windowRMSValues: [Double] = []

        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: chunkSize)
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0, let channels = buffer.floatChannelData else { break }
            let channelCount = Int(format.channelCount)

            for frameIndex in 0..<frameLength {
                var sum: Double = 0
                for channelIndex in 0..<channelCount {
                    let sample = Double(channels[channelIndex][frameIndex])
                    sum += sample * sample
                }

                windowEnergy += sum / Double(max(channelCount, 1))
                windowFrameCount += 1

                if windowFrameCount >= windowFrames {
                    windowRMSValues.append(sqrt(windowEnergy / Double(windowFrameCount)))
                    windowEnergy = 0
                    windowFrameCount = 0
                }
            }
        }

        if windowFrameCount > 0 {
            windowRMSValues.append(sqrt(windowEnergy / Double(windowFrameCount)))
        }

        guard !windowRMSValues.isEmpty else { return 0 }

        let baselineWindowCount = min(windowRMSValues.count, max(1, Int(3.0 / 0.08)))
        let baseline = Array(windowRMSValues.prefix(baselineWindowCount)).sorted()
        let baselineRMS = baseline[baseline.count / 2]
        let speechThreshold = max(0.012, baselineRMS * 5.0)
        let requiredWindows = 3
        var runLength = 0
        var candidateIndex: Int?

        for (index, rms) in windowRMSValues.enumerated() {
            if rms >= speechThreshold {
                if candidateIndex == nil {
                    candidateIndex = index
                }
                runLength += 1

                if runLength >= requiredWindows, let candidateIndex {
                    let offset = Double(candidateIndex * windowFrames) / sampleRate
                    AppLog.transcription.info(
                        "whisperLeadingSpeechOffset offset=\(offset, privacy: .public) threshold=\(speechThreshold, privacy: .public) baseline=\(baselineRMS, privacy: .public)"
                    )
                    return max(0, offset)
                }
            } else {
                candidateIndex = nil
                runLength = 0
            }
        }

        AppLog.transcription.info(
            "whisperLeadingSpeechOffset offset=0 threshold=\(speechThreshold, privacy: .public) baseline=\(baselineRMS, privacy: .public)"
        )
        return 0
    }

    private static func runWhisperCLI(
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

    private static func executeWhisperCLI(
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

    private static func whisperEnvironment(for cliPath: String) -> [String: String] {
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

    private static func cleanWhisperError(
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

    private static func parseWhisperOutput(_ output: String) -> [SubtitleSegment] {
        output
            .components(separatedBy: .newlines)
            .compactMap(parseWhisperLine)
    }

    private func alignLeadingSegmentStartIfNeeded(
        _ segments: [SubtitleSegment],
        offset: TimeInterval
    ) -> [SubtitleSegment] {
        guard offset > 0.4, let firstStart = segments.first?.start, firstStart < 0.5 else {
            return segments
        }

        AppLog.transcription.info(
            "whisperLeadingStartAligned offset=\(offset, privacy: .public) segmentCount=\(segments.count, privacy: .public)"
        )

        var aligned = segments
        let first = aligned[0]
        aligned[0] = SubtitleSegment(
            id: first.id,
            start: min(offset, max(first.start, first.end - 0.2)),
            end: first.end,
            text: first.text,
            words: nil
        )
        return aligned
    }

    private static func parseWhisperLine(_ line: String) -> SubtitleSegment? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["),
              let closeBracket = trimmed.firstIndex(of: "]")
        else {
            return nil
        }

        let timeString = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closeBracket])
        let parts = timeString.components(separatedBy: "-->")
        guard parts.count == 2 else { return nil }

        let start = parseWhisperTime(parts[0].trimmingCharacters(in: .whitespaces))
        let end = parseWhisperTime(parts[1].trimmingCharacters(in: .whitespaces))
        let text = String(trimmed[trimmed.index(after: closeBracket)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        return SubtitleSegment(start: start, end: max(end, start + 0.1), text: text)
    }

    private static func parseWhisperTime(_ string: String) -> TimeInterval {
        let parts = string.components(separatedBy: ":")
        guard parts.count == 3,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2])
        else {
            return 0
        }
        return hours * 3600 + minutes * 60 + seconds
    }
}

final class CloudASRProvider: TranscriptionProvider {
    private let apiURL: String
    private let apiKey: String
    private let model: String
    private let segmentationConfiguration: SubtitleSegmentationConfiguration

    init(
        apiURL: String,
        apiKey: String,
        model: String,
        segmentationConfiguration: SubtitleSegmentationConfiguration
    ) {
        self.apiURL = apiURL
        self.apiKey = apiKey
        self.model = model
        self.segmentationConfiguration = segmentationConfiguration
    }

    func transcribe(audioURL: URL, language: String) async throws -> [SubtitleSegment] {
        AppLog.transcription.info(
            "cloudASR configuration urlValid=\(Self.validatedEndpoint(self.apiURL) != nil, privacy: .public) keyPresent=\(!self.apiKey.isEmpty, privacy: .public) modelPresent=\(!self.model.isEmpty, privacy: .public) model=\(self.model, privacy: .public)"
        )
        guard !apiKey.isEmpty else {
            throw TranscriptionError.cloudNotConfigured
        }

        // 与 Git 一致：qwen3-asr-flash-filetrans / transcription 端点 → 异步 filetrans
        // filetrans 不能走 OpenAI compatible-mode（会 404 model_not_supported）
        if usesFiletransModel || isDashScopeAsyncURL {
            guard Self.validatedEndpoint(asyncTranscriptionURL) != nil else {
                throw TranscriptionError.cloudNotConfigured
            }
            return try await transcribeDashScopeAsync(audioURL: audioURL, language: language)
        }

        guard Self.validatedEndpoint(apiURL) != nil else {
            throw TranscriptionError.cloudNotConfigured
        }

        if isDashScopeCompatibleModeURL {
            return try await transcribeDashScopeCompatible(audioURL: audioURL, language: language)
        }

        return try await transcribeWhisperCompatible(audioURL: audioURL, language: language)
    }

    static func validatedEndpoint(_ rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains("{WorkspaceId}"),
              !trimmed.contains("{workspaceId}"),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host,
              !host.isEmpty,
              !host.contains("{"),
              !host.contains("}") else {
            return nil
        }
        return url
    }

    private var usesFiletransModel: Bool {
        model.lowercased().contains("filetrans")
    }

    private var isDashScopeCompatibleModeURL: Bool {
        guard let url = URL(string: apiURL) else { return false }
        return url.path.hasSuffix("/compatible-mode/v1/chat/completions")
    }

    private var isDashScopeAsyncURL: Bool {
        guard let url = URL(string: apiURL) else { return false }
        return url.path.hasSuffix("/api/v1/services/audio/asr/transcription")
    }

    /// Git 异步端点：.../api/v1/services/audio/asr/transcription
    /// 若设置里误填了 compatible-mode，按同 host 改回 transcription 路径。
    private var asyncTranscriptionURL: String {
        if isDashScopeAsyncURL {
            return apiURL
        }
        if let url = URL(string: apiURL), let host = url.host, !host.isEmpty {
            let scheme = (url.scheme?.isEmpty == false) ? url.scheme! : "https"
            return "\(scheme)://\(host)/api/v1/services/audio/asr/transcription"
        }
        return "https://dashscope.aliyuncs.com/api/v1/services/audio/asr/transcription"
    }

    private func transcribeDashScopeCompatible(audioURL: URL, language: String) async throws -> [SubtitleSegment] {
        let audioData = try Data(contentsOf: audioURL)
        let mimeType = switch audioURL.pathExtension.lowercased() {
        case "m4a": "audio/mp4"
        case "mp3": "audio/mpeg"
        default: "audio/wav"
        }
        let dataURI = "data:\(mimeType);base64,\(audioData.base64EncodedString())"
        let body: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "input_audio",
                            "input_audio": [
                                "data": dataURI
                            ]
                        ]
                    ]
                ]
            ],
            "stream": false,
            "asr_options": dashScopeASROptions(language: language)
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        guard let endpoint = Self.validatedEndpoint(apiURL) else {
            throw TranscriptionError.cloudNotConfigured
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData
        request.timeoutInterval = 180

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let message = String(data: data, encoding: .utf8) ?? ""
            throw TranscriptionError.cloudRequestFailedWithDetail("DashScope 兼容模式失败 HTTP \(code): \(message.prefix(200))")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw TranscriptionError.cloudResponseInvalid
        }

        let duration = await audioDuration(url: audioURL)
        return TimedSubtitleSegmenter.segmentEstimated(
            approximateSegments(from: content, duration: duration),
            configuration: segmentationConfiguration
        )
    }

    private func transcribeDashScopeAsync(audioURL: URL, language: String) async throws -> [SubtitleSegment] {
        // filetrans 官方要求公网/临时 URL，不能把整文件 Base64 塞进请求体（长音频会 413 RequestTooLarge）。
        // 使用百炼免费临时存储：getPolicy → 上传 → oss:// 短链 → 异步转写。
        let fileURL = try await uploadLocalAudioToDashScopeTempStorage(audioURL: audioURL)

        let body: [String: Any] = [
            "model": model,
            "input": ["file_url": fileURL],
            "parameters": dashScopeTaskParameters(language: language)
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        guard let endpoint = Self.validatedEndpoint(asyncTranscriptionURL) else {
            throw TranscriptionError.cloudNotConfigured
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("enable", forHTTPHeaderField: "X-DashScope-Async")
        // 解析 oss:// 临时地址时必须带此 Header
        request.setValue("enable", forHTTPHeaderField: "X-DashScope-OssResourceResolve")
        request.httpBody = bodyData
        request.timeoutInterval = 120

        AppLog.transcription.info(
            "cloudASR asyncSubmit endpoint=\(endpoint.absoluteString, privacy: .public) model=\(self.model, privacy: .public) fileURLScheme=\(fileURL.hasPrefix("oss://") ? "oss" : "other", privacy: .public)"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let message = String(data: data, encoding: .utf8) ?? ""
            throw TranscriptionError.cloudRequestFailedWithDetail("DashScope 提交失败 HTTP \(code): \(message.prefix(200))")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let output = json["output"] as? [String: Any],
              let taskID = output["task_id"] as? String
        else {
            throw TranscriptionError.cloudResponseInvalid
        }

        let resultURL = try await pollDashScopeTask(taskID: taskID)
        return try await downloadDashScopeResult(url: resultURL, audioURL: audioURL)
    }

    /// 百炼临时存储：本地文件 → oss:// 临时 URL（约 48 小时有效，无需自建 OSS）。
    private func uploadLocalAudioToDashScopeTempStorage(audioURL: URL) async throws -> String {
        let policy = try await fetchDashScopeUploadPolicy()

        guard let uploadHost = policy["upload_host"] as? String,
              let uploadDir = policy["upload_dir"] as? String,
              let accessKeyId = policy["oss_access_key_id"] as? String,
              let signature = policy["signature"] as? String,
              let policyToken = policy["policy"] as? String,
              let objectACL = policy["x_oss_object_acl"] as? String,
              let forbidOverwrite = policy["x_oss_forbid_overwrite"] as? String,
              let uploadHostURL = URL(string: uploadHost)
        else {
            throw TranscriptionError.cloudRequestFailedWithDetail("DashScope 上传凭证字段不完整")
        }

        let originalName = audioURL.lastPathComponent
        let safeName = originalName.isEmpty ? "audio.m4a" : originalName
        // 避免同名冲突（x-oss-forbid-overwrite 常为 true）
        let objectName = "subforge-\(UUID().uuidString.lowercased())-\(safeName)"
        let objectKey = "\(uploadDir)/\(objectName)"

        let fileData = try Data(contentsOf: audioURL)
        if let maxMB = Self.intValue(policy["max_file_size_mb"]), maxMB > 0 {
            let maxBytes = maxMB * 1024 * 1024
            if fileData.count > maxBytes {
                throw TranscriptionError.cloudRequestFailedWithDetail(
                    "音频文件过大（\(Self.formatByteCount(fileData.count))），当前模型临时上传上限约 \(maxMB)MB"
                )
            }
        }

        let boundary = "----SubForgeDashScope-\(UUID().uuidString)"
        var body = Data()

        func appendTextField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        // 官方要求 file 必须是最后一个表单域
        appendTextField("OSSAccessKeyId", accessKeyId)
        appendTextField("Signature", signature)
        appendTextField("policy", policyToken)
        appendTextField("x-oss-object-acl", objectACL)
        appendTextField("x-oss-forbid-overwrite", forbidOverwrite)
        appendTextField("key", objectKey)
        appendTextField("success_action_status", "200")

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(objectName)\"\r\n".data(using: .utf8)!
        )
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: uploadHostURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 300

        AppLog.transcription.info(
            "cloudASR tempUpload bytes=\(fileData.count, privacy: .public) keySuffix=\(objectName, privacy: .public)"
        )

        let (responseData, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard code == 200 else {
            let message = String(data: responseData, encoding: .utf8) ?? ""
            throw TranscriptionError.cloudRequestFailedWithDetail(
                "DashScope 临时上传失败 HTTP \(code): \(message.prefix(200))"
            )
        }

        return "oss://\(objectKey)"
    }

    private func fetchDashScopeUploadPolicy() async throws -> [String: Any] {
        let candidates = dashScopeUploadPolicyEndpointCandidates()
        var lastError: String = "未知错误"

        for endpoint in candidates {
            var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
            components?.queryItems = [
                URLQueryItem(name: "action", value: "getPolicy"),
                URLQueryItem(name: "model", value: model)
            ]
            guard let url = components?.url else { continue }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 60

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                guard code == 200 else {
                    lastError = "HTTP \(code): \(String(data: data, encoding: .utf8) ?? "")"
                    AppLog.transcription.error(
                        "cloudASR getPolicy failed endpoint=\(url.absoluteString, privacy: .public) \(lastError, privacy: .public)"
                    )
                    continue
                }

                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let policy = json["data"] as? [String: Any]
                else {
                    lastError = "响应缺少 data 字段"
                    continue
                }

                AppLog.transcription.info(
                    "cloudASR getPolicy ok endpoint=\(url.absoluteString, privacy: .public)"
                )
                return policy
            } catch {
                lastError = error.localizedDescription
            }
        }

        throw TranscriptionError.cloudRequestFailedWithDetail(
            "获取 DashScope 上传凭证失败：\(lastError.prefix(200))"
        )
    }

    /// 优先用设置里的业务空间域名，失败再回退公共 dashscope 域名。
    private func dashScopeUploadPolicyEndpointCandidates() -> [URL] {
        var urls: [URL] = []
        if let requestURL = URL(string: asyncTranscriptionURL),
           let host = requestURL.host,
           !host.isEmpty {
            let scheme = (requestURL.scheme?.isEmpty == false) ? requestURL.scheme! : "https"
            if let url = URL(string: "\(scheme)://\(host)/api/v1/uploads") {
                urls.append(url)
            }
        }

        let fallbacks = [
            "https://dashscope.aliyuncs.com/api/v1/uploads",
            "https://dashscope-intl.aliyuncs.com/api/v1/uploads"
        ]
        for raw in fallbacks {
            if let url = URL(string: raw), !urls.contains(url) {
                urls.append(url)
            }
        }
        return urls
    }

    private static func formatByteCount(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let number as Int:
            return number
        case let number as NSNumber:
            return number.intValue
        case let text as String:
            return Int(text)
        default:
            return nil
        }
    }

    private func pollDashScopeTask(taskID: String) async throws -> String {
        guard let pollURL = dashScopeTaskPollingURL(taskID: taskID) else {
            throw TranscriptionError.cloudResponseInvalid
        }

        var request = URLRequest(url: pollURL)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 300

        for _ in 0..<60 {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let output = json["output"] as? [String: Any],
                  let status = output["task_status"] as? String
            else {
                throw TranscriptionError.cloudResponseInvalid
            }

            switch status {
            case "SUCCEEDED":
                if let result = output["result"] as? [String: String],
                   let transcriptionURL = result["transcription_url"] {
                    return transcriptionURL
                }
                if let result = output["result"] as? [String: Any],
                   let transcriptionURL = result["transcription_url"] as? String {
                    return transcriptionURL
                }
                throw TranscriptionError.cloudResponseInvalid
            case "FAILED":
                let message = output["message"] as? String ?? "未知错误"
                throw TranscriptionError.cloudRequestFailedWithDetail("DashScope 任务失败：\(message)")
            default:
                try await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }

        throw TranscriptionError.timeout
    }

    private func dashScopeTaskPollingURL(taskID: String) -> URL? {
        guard let requestURL = URL(string: asyncTranscriptionURL),
              var components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        components.path = "/api/v1/tasks/\(taskID)"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private func dashScopeASROptions(language: String) -> [String: Any] {
        var options: [String: Any] = ["enable_itn": true]
        if let normalized = normalizeDashScopeLanguage(language) {
            options["language"] = normalized
        }
        return options
    }

    private func dashScopeTaskParameters(language: String) -> [String: Any] {
        var parameters: [String: Any] = [
            "channel_id": [0],
            "enable_itn": true,
            "enable_words": true
        ]
        if let normalized = normalizeDashScopeLanguage(language) {
            parameters["language"] = normalized
        }
        return parameters
    }

    private func normalizeDashScopeLanguage(_ language: String) -> String? {
        switch language {
        case "zh-CN", "zh-TW":
            return "zh"
        case "en-US":
            return "en"
        case "ja-JP":
            return "ja"
        default:
            return nil
        }
    }

    private func approximateSegments(from text: String, duration: TimeInterval) -> [SubtitleSegment] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let enders = CharacterSet(charactersIn: "。！？!?；;")
        var chunks: [String] = []
        var current = ""

        for scalar in trimmed.unicodeScalars {
            current.unicodeScalars.append(scalar)
            if enders.contains(scalar) {
                let sentence = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty {
                    chunks.append(sentence)
                }
                current = ""
            }
        }

        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            chunks.append(tail)
        }

        if chunks.isEmpty {
            chunks = [trimmed]
        }

        let totalUnits = max(chunks.reduce(0) { $0 + max($1.count, 1) }, 1)
        let totalDuration = max(duration, 0.1)
        var cursor: TimeInterval = 0

        return chunks.enumerated().map { index, chunk in
            let weight = Double(max(chunk.count, 1)) / Double(totalUnits)
            let segmentDuration = index == chunks.count - 1 ? max(totalDuration - cursor, 0.1) : max(totalDuration * weight, 0.2)
            let start = cursor
            let end = min(totalDuration, cursor + segmentDuration)
            cursor = end
            return SubtitleSegment(start: start, end: max(end, start + 0.1), text: chunk)
        }
    }

    private func downloadDashScopeResult(url: String, audioURL: URL) async throws -> [SubtitleSegment] {
        guard let resolvedURL = resolvedDashScopeResultURL(from: url) else {
            throw TranscriptionError.cloudResponseInvalid
        }

        let (data, _) = try await URLSession.shared.data(from: resolvedURL)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranscriptionError.cloudResponseInvalid
        }

        if let transcripts = json["transcripts"] as? [[String: Any]],
           let first = transcripts.first,
           let sentences = first["sentences"] as? [[String: Any]] {
            var timedWords: [SubtitleWord] = []

            for sentence in sentences {
                if let words = dashScopeSentenceWords(sentence), !words.isEmpty {
                    timedWords.append(contentsOf: words)
                    continue
                }

                guard let text = (sentence["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty else {
                    continue
                }

                let start = (sentence["begin_time"] as? Double ?? 0) / 1000.0
                let end = (sentence["end_time"] as? Double ?? 0) / 1000.0
                timedWords.append(
                    SubtitleWord(start: start, end: max(end, start + 0.1), text: text)
                )
            }

            if !timedWords.isEmpty {
                return TimedSubtitleSegmenter.segment(
                    timedWords,
                    configuration: segmentationConfiguration
                )
            }
        }

        if let transcripts = json["transcripts"] as? [[String: Any]],
           let first = transcripts.first,
           let text = first["text"] as? String,
           !text.isEmpty {
            let duration = await audioDuration(url: audioURL)
            return TimedSubtitleSegmenter.segmentEstimated(
                approximateSegments(from: text, duration: duration),
                configuration: segmentationConfiguration
            )
        }

        throw TranscriptionError.cloudResponseInvalid
    }

    private func dashScopeSentenceWords(_ sentence: [String: Any]) -> [SubtitleWord]? {
        guard let words = sentence["words"] as? [[String: Any]], !words.isEmpty else {
            return nil
        }

        let results = words.compactMap { word -> SubtitleWord? in
            guard let token = word["text"] as? String else { return nil }
            let punctuation = word["punctuation"] as? String ?? ""
            let start = (word["begin_time"] as? Double ?? 0) / 1000.0
            let end = (word["end_time"] as? Double ?? start * 1000) / 1000.0
            return SubtitleWord(
                start: start,
                end: max(end, start + 0.1),
                text: token + punctuation
            )
        }
        return results.isEmpty ? nil : results
    }

    private func resolvedDashScopeResultURL(from rawURL: String) -> URL? {
        guard var components = URLComponents(string: rawURL) else {
            return nil
        }

        if components.scheme == "http",
           let host = components.host,
           host.contains("aliyuncs.com") {
            components.scheme = "https"
        }

        return components.url
    }

    private func transcribeWhisperCompatible(audioURL: URL, language: String) async throws -> [SubtitleSegment] {
        let boundary = "----SubForge-\(UUID().uuidString)"
        var body = Data()

        func appendField(_ name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        appendField("model", value: model)
        appendField("language", value: language.hasPrefix("zh") ? "zh" : language)
        appendField("response_format", value: "verbose_json")

        let audioData = try Data(contentsOf: audioURL)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(audioURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/mpeg\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        request.timeoutInterval = 600

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let message = String(data: data, encoding: .utf8) ?? ""
            throw TranscriptionError.cloudRequestFailedWithDetail("HTTP \(code): \(message.prefix(200))")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranscriptionError.cloudResponseInvalid
        }

        if let segmentsData = json["segments"] as? [[String: Any]] {
            let segments = segmentsData.compactMap { dict -> SubtitleSegment? in
                guard let start = dict["start"] as? Double,
                      let end = dict["end"] as? Double,
                      let text = (dict["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty else {
                    return nil
                }

                return SubtitleSegment(start: start, end: max(end, start + 0.1), text: text)
            }

            if !segments.isEmpty {
                return TimedSubtitleSegmenter.segmentEstimated(
                    segments,
                    configuration: segmentationConfiguration
                )
            }
        }

        if let text = json["text"] as? String,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let duration = await audioDuration(url: audioURL)
            return TimedSubtitleSegmenter.segmentEstimated(
                approximateSegments(from: text, duration: duration),
                configuration: segmentationConfiguration
            )
        }

        throw TranscriptionError.cloudResponseInvalid
    }

    private func audioDuration(url: URL) async -> TimeInterval {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            return seconds.isNaN ? 10.0 : seconds
        } catch {
            return 10.0
        }
    }
}

enum TranscriptionError: LocalizedError {
    case notAuthorized(SFSpeechRecognizerAuthorizationStatus)
    case recognizerUnavailable(String)
    case cliUnavailable
    case modelUnavailable
    case funASRCLIUnavailable
    case funASRModelUnavailable
    case funASRVADUnavailable
    case funASRExecutionFailed(String)
    case audioConversionFailed
    /// 无法读取用户选择的音频（常见于沙箱未拿到安全作用域，或拖入路径无效）。
    case audioSourceUnreadable
    case whisperExecutionFailed(String)
    case cloudNotConfigured
    case cloudRequestFailedWithDetail(String)
    case cloudResponseInvalid
    case timeout
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .notAuthorized(let status):
            "语音识别未授权（状态: \(status.rawValue)）"
        case .recognizerUnavailable(let language):
            "语言 \(language) 的识别器不可用"
        case .cliUnavailable:
            "whisper-cli 未安装，请先在本机安装 whisper-cpp"
        case .modelUnavailable:
            "Whisper 模型未下载，请先在设置中下载模型"
        case .funASRCLIUnavailable:
            "未检测到 llama-funasr-sensevoice。请通过 script/download_funasr_runtime.sh 安装，或重新打包应用。"
        case .funASRModelUnavailable:
            "FunASR SenseVoice 模型未下载，请先在设置中下载模型"
        case .funASRVADUnavailable:
            "FunASR VAD 模型未下载，请先在设置中下载 SenseVoice（会同时下载 VAD）"
        case .funASRExecutionFailed(let message):
            "FunASR 执行失败：\(message)"
        case .audioConversionFailed:
            "音频转换失败（afconvert）"
        case .audioSourceUnreadable:
            "无法读取所选音频。请用「打开」按钮重新选择文件，不要只依赖失效的最近项目路径；若从访达拖入失败，请改用打开面板。"
        case .whisperExecutionFailed(let message):
            "whisper-cli 执行失败：\(message)"
        case .cloudNotConfigured:
            "云端 ASR 未配置，请填写 Base URL、Key 和模型名"
        case .cloudRequestFailedWithDetail(let detail):
            "云端 ASR 错误：\(detail)"
        case .cloudResponseInvalid:
            "云端 ASR 响应格式异常"
        case .timeout:
            "转写超时（5分钟）"
        case .emptyResult:
            "没有识别出可用字幕"
        }
    }
}

enum TranscriptionService {
    static func createProvider(settings: AppSettings) -> TranscriptionProvider {
        var resolvedSettings = settings
        let segmentationConfiguration = SubtitleSegmentationConfiguration(
            maxCharacters: resolvedSettings.effectiveMaxSubtitleLength
        )

        switch resolvedSettings.transcriptionEngine {
        case .whisperLocal:
            return WhisperCppProvider(
                model: resolvedSettings.whisperModel,
                segmentationConfiguration: segmentationConfiguration
            )
        case .funASRLocal:
            return FunASRSenseVoiceProvider(
                model: .sensevoiceSmallQ8,
                segmentationConfiguration: segmentationConfiguration
            )
        case .appleSpeech:
            return AppleSpeechProvider(segmentationConfiguration: segmentationConfiguration)
        case .officialSmart:
            return OfficialSmartSubtitleProvider(segmentationConfiguration: segmentationConfiguration)
        case .cloudASR:
            SettingsStore.hydrateSecrets(into: &resolvedSettings, includeASR: true, includeLLM: false)
            return CloudASRProvider(
                apiURL: resolvedSettings.effectiveASRURL,
                apiKey: resolvedSettings.cloudASRKey,
                model: resolvedSettings.effectiveASRModel,
                segmentationConfiguration: segmentationConfiguration
            )
        }
    }
}
