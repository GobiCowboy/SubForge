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
                let rawSegments = result.bestTranscription.segments.map { segment in
                    SubtitleSegment(
                        start: segment.timestamp,
                        end: segment.timestamp + segment.duration,
                        text: segment.substring
                    )
                }
                latestSegments = SubtitleSegmentationService.refine(self.mergeIntoSentences(rawSegments))

                if result.isFinal && !hasResumed {
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

    private func mergeIntoSentences(_ segments: [SubtitleSegment]) -> [SubtitleSegment] {
        guard !segments.isEmpty else { return [] }

        let sentenceEnders: Set<Character> = ["。", "！", "？", "!", "?", ".", "；", ";", "\n"]
        let clauseEnders: Set<Character> = ["，", ",", "、", "：", ":", "—", "–"]

        var results: [SubtitleSegment] = []
        var currentText = ""
        var currentStart: TimeInterval = 0
        var currentEnd: TimeInterval = 0

        for segment in segments {
            let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let gapFromPrevious = currentText.isEmpty ? 0 : max(0, segment.start - currentEnd)

            if currentText.isEmpty {
                currentStart = segment.start
            }

            currentText += trimmed
            currentEnd = segment.end

            let lastCharacter = trimmed.last ?? Character(" ")
            if sentenceEnders.contains(lastCharacter) {
                results.append(
                    SubtitleSegment(
                        start: currentStart,
                        end: currentEnd,
                        text: currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                )
                currentText = ""
                continue
            }

            if clauseEnders.contains(lastCharacter) && currentText.count >= 15 {
                results.append(
                    SubtitleSegment(
                        start: currentStart,
                        end: currentEnd,
                        text: currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                )
                currentText = ""
                continue
            }

            if gapFromPrevious > 0.65 || currentText.count >= 25 {
                results.append(
                    SubtitleSegment(
                        start: currentStart,
                        end: currentEnd,
                        text: currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                )
                currentText = ""
            }
        }

        if !currentText.isEmpty {
            results.append(
                SubtitleSegment(
                    start: currentStart,
                    end: currentEnd,
                    text: currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
        }

        return results
    }
}

final class WhisperCppProvider: TranscriptionProvider {
    private let model: WhisperModel

    init(model: WhisperModel) {
        self.model = model
    }

    func transcribe(audioURL: URL, language: String) async throws -> [SubtitleSegment] {
        let cliPath = try resolveCLIPath()
        let modelPath = try resolveModelPath()
        let wavURL = FileManager.default.temporaryDirectory.appendingPathComponent("subforge_whisper_\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: wavURL) }

        try await Task.detached(priority: .userInitiated) {
            try Self.convertToWAV(input: audioURL, output: wavURL)
        }.value

        let leadingSilenceOffset = (try? Self.leadingAudibleOffset(in: wavURL)) ?? 0

        let output = try await Task.detached(priority: .userInitiated) {
            try Self.runWhisperCLI(cliPath: cliPath, modelPath: modelPath, wavURL: wavURL, language: language)
        }.value

        let rawSegments = alignLeadingSegmentStartIfNeeded(
            parseWhisperOutput(output),
            offset: leadingSilenceOffset
        )
        let parsed = SubtitleSegmentationService.refine(rawSegments)
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
        language: String
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = [
            "-m", modelPath,
            "-f", wavURL.path,
            "-l", language.hasPrefix("zh") ? "zh" : language,
            "-t", "4",
            "--max-len", "20",
            "--no-gpu",
            "--no-prints"
        ]

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

        return output
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

    private func parseWhisperOutput(_ output: String) -> [SubtitleSegment] {
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
            text: first.text
        )
        return aligned
    }

    private func parseWhisperLine(_ line: String) -> SubtitleSegment? {
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

    private func parseWhisperTime(_ string: String) -> TimeInterval {
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
    private let preferredSegmentDuration: TimeInterval = 3.8
    private let hardSegmentDuration: TimeInterval = 5.2

    private let apiURL: String
    private let apiKey: String
    private let model: String

    init(apiURL: String, apiKey: String, model: String) {
        self.apiURL = apiURL
        self.apiKey = apiKey
        self.model = model
    }

    func transcribe(audioURL: URL, language: String) async throws -> [SubtitleSegment] {
        guard !apiURL.isEmpty, !apiKey.isEmpty else {
            throw TranscriptionError.cloudNotConfigured
        }

        if isDashScopeCompatibleModeURL {
            return try await transcribeDashScopeCompatible(audioURL: audioURL, language: language)
        }

        if isDashScopeAsyncURL {
            return try await transcribeDashScopeAsync(audioURL: audioURL, language: language)
        }

        return try await transcribeWhisperCompatible(audioURL: audioURL, language: language)
    }

    private var isDashScopeCompatibleModeURL: Bool {
        guard let url = URL(string: apiURL) else { return false }
        return url.path.hasSuffix("/compatible-mode/v1/chat/completions")
    }

    private var isDashScopeAsyncURL: Bool {
        guard let url = URL(string: apiURL) else { return false }
        return url.path.hasSuffix("/api/v1/services/audio/asr/transcription")
    }

    private func transcribeDashScopeCompatible(audioURL: URL, language: String) async throws -> [SubtitleSegment] {
        let audioData = try Data(contentsOf: audioURL)
        let mimeType = switch audioURL.pathExtension.lowercased() {
        case "m4a", "mp4": "audio/mp4"
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
        var request = URLRequest(url: URL(string: apiURL)!)
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
        return approximateSegments(from: content, duration: duration)
    }

    private func transcribeDashScopeAsync(audioURL: URL, language: String) async throws -> [SubtitleSegment] {
        let audioData = try Data(contentsOf: audioURL)
        let mimeType = switch audioURL.pathExtension.lowercased() {
        case "m4a", "mp4": "audio/mp4"
        case "mp3": "audio/mpeg"
        default: "audio/wav"
        }
        let fileURL = "data:\(mimeType);base64,\(audioData.base64EncodedString())"

        let body: [String: Any] = [
            "model": model,
            "input": ["file_url": fileURL],
            "parameters": dashScopeTaskParameters(language: language)
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("enable", forHTTPHeaderField: "X-DashScope-Async")
        request.httpBody = bodyData
        request.timeoutInterval = 120

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
        guard let requestURL = URL(string: apiURL),
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
            var segments: [SubtitleSegment] = []

            for sentence in sentences {
                if let splitFromWords = splitDashScopeSentenceWords(sentence), !splitFromWords.isEmpty {
                    segments.append(contentsOf: splitFromWords)
                    continue
                }

                guard let text = (sentence["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty else {
                    continue
                }

                let start = (sentence["begin_time"] as? Double ?? 0) / 1000.0
                let end = (sentence["end_time"] as? Double ?? 0) / 1000.0
                segments.append(contentsOf: splitLongSegment(SubtitleSegment(start: start, end: max(end, start + 0.1), text: text)))
            }

            if !segments.isEmpty {
                return SubtitleSegmentationService.refine(segments)
            }
        }

        if let transcripts = json["transcripts"] as? [[String: Any]],
           let first = transcripts.first,
           let text = first["text"] as? String,
           !text.isEmpty {
            let duration = await audioDuration(url: audioURL)
            return SubtitleSegmentationService.refine(approximateSegments(from: text, duration: duration))
        }

        throw TranscriptionError.cloudResponseInvalid
    }

    private func splitDashScopeSentenceWords(_ sentence: [String: Any]) -> [SubtitleSegment]? {
        guard let words = sentence["words"] as? [[String: Any]], !words.isEmpty else {
            return nil
        }

        var results: [SubtitleSegment] = []
        var currentText = ""
        var currentStart: TimeInterval?
        var currentEnd: TimeInterval = 0

        func flush() {
            let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let start = currentStart, !text.isEmpty else { return }
            results.append(
                SubtitleSegment(
                    start: start,
                    end: max(currentEnd, start + 0.1),
                    text: text
                )
            )
            currentText = ""
            currentStart = nil
            currentEnd = 0
        }

        for word in words {
            guard let token = word["text"] as? String else { continue }
            let punctuation = word["punctuation"] as? String ?? ""
            let start = (word["begin_time"] as? Double ?? 0) / 1000.0
            let end = (word["end_time"] as? Double ?? start * 1000) / 1000.0

            if currentStart == nil {
                currentStart = start
            }

            currentText += token + punctuation
            currentEnd = max(currentEnd, end)

            let duration = currentEnd - (currentStart ?? start)
            let strongBreak = ["。", "！", "？", "!", "?"].contains(punctuation)
            let softBreak = ["，", "、", "；", ";", "：", ":"].contains(punctuation)

            if strongBreak || duration >= hardSegmentDuration || (softBreak && duration >= preferredSegmentDuration) {
                flush()
            }
        }

        flush()

        return results.isEmpty ? nil : results
    }

    private func splitLongSegment(_ segment: SubtitleSegment) -> [SubtitleSegment] {
        let duration = segment.end - segment.start
        let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard duration > hardSegmentDuration, !text.isEmpty else {
            return [segment]
        }

        let delimiters = CharacterSet(charactersIn: "，。、；：！？,.;:!?")
        var chunks: [String] = []
        var current = ""

        for scalar in text.unicodeScalars {
            current.unicodeScalars.append(scalar)
            if delimiters.contains(scalar), current.count >= 6 {
                let chunk = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !chunk.isEmpty {
                    chunks.append(chunk)
                }
                current = ""
            }
        }

        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            chunks.append(tail)
        }

        guard chunks.count > 1 else {
            return [segment]
        }

        let totalUnits = max(chunks.reduce(0) { $0 + max($1.count, 1) }, 1)
        var cursor = segment.start

        return chunks.enumerated().map { index, chunk in
            let weight = Double(max(chunk.count, 1)) / Double(totalUnits)
            let chunkDuration = index == chunks.count - 1
                ? max(segment.end - cursor, 0.1)
                : max(duration * weight, 0.35)
            let start = cursor
            let end = min(segment.end, cursor + chunkDuration)
            cursor = end
            return SubtitleSegment(start: start, end: max(end, start + 0.1), text: chunk)
        }
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
                return SubtitleSegmentationService.refine(segments)
            }
        }

        if let text = json["text"] as? String,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let duration = await audioDuration(url: audioURL)
            return SubtitleSegmentationService.refine(approximateSegments(from: text, duration: duration))
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
    case audioConversionFailed
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
        case .audioConversionFailed:
            "音频转换失败（afconvert）"
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
        switch settings.transcriptionEngine {
        case .whisperLocal:
            WhisperCppProvider(model: settings.whisperModel)
        case .appleSpeech:
            AppleSpeechProvider()
        case .cloudASR:
            CloudASRProvider(
                apiURL: settings.effectiveASRURL,
                apiKey: settings.cloudASRKey,
                model: settings.effectiveASRModel
            )
        }
    }
}
