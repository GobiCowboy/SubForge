import Foundation
import Speech
import AVFoundation

/// 转写服务统一协议
protocol TranscriptionProvider {
    func transcribe(audioURL: URL, language: String) async throws -> [SubtitleSegment]
    func testAvailability() async -> TranscriptionTestResult
}

struct TranscriptionTestResult {
    let available: Bool
    let message: String
    let duration: TimeInterval?
}

/// Apple Speech 转写实现
final class AppleSpeechProvider: TranscriptionProvider {
    func transcribe(audioURL: URL, language: String) async throws -> [SubtitleSegment] {
        // 请求授权
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
            var lastSegments: [SubtitleSegment] = []

            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    if !hasResumed {
                        hasResumed = true
                        if lastSegments.isEmpty {
                            continuation.resume(throwing: error)
                        } else {
                            // 有部分结果就返回
                            continuation.resume(returning: lastSegments)
                        }
                    }
                    return
                }

                guard let result = result else { return }

                // 收集最新的 segments（逐词级别）
                let rawSegments = result.bestTranscription.segments.map { seg -> SubtitleSegment in
                    SubtitleSegment(
                        start: seg.timestamp,
                        end: seg.timestamp + seg.duration,
                        text: seg.substring
                    )
                }
                let merged = self.mergeIntoSentences(rawSegments)
                if !merged.isEmpty {
                    lastSegments = merged
                }

                if result.isFinal && !hasResumed {
                    hasResumed = true
                    if lastSegments.isEmpty {
                        let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty {
                            continuation.resume(returning: [SubtitleSegment(start: 0, end: 1, text: text)])
                        } else {
                            continuation.resume(returning: [])
                        }
                    } else {
                        continuation.resume(returning: lastSegments)
                    }
                }
            }

            // 超时保护
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000_000) // 5分钟
                if !hasResumed {
                    hasResumed = true
                    task.cancel()
                    if lastSegments.isEmpty {
                        continuation.resume(throwing: TranscriptionError.timeout)
                    } else {
                        continuation.resume(returning: lastSegments)
                    }
                }
            }
        }
    }

    func testAvailability() async -> TranscriptionTestResult {
        let start = Date()
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        let elapsed = Date().timeIntervalSince(start)

        switch status {
        case .authorized:
            let locale = Locale(identifier: "zh-CN")
            if let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable {
                return TranscriptionTestResult(available: true, message: "可用，中文识别就绪", duration: elapsed)
            } else {
                return TranscriptionTestResult(available: false, message: "中文识别不可用", duration: elapsed)
            }
        case .denied:
            return TranscriptionTestResult(available: false, message: "语音识别权限被拒绝", duration: elapsed)
        case .restricted:
            return TranscriptionTestResult(available: false, message: "语音识别受限制", duration: elapsed)
        case .notDetermined:
            return TranscriptionTestResult(available: false, message: "权限未确定", duration: elapsed)
        @unknown default:
            return TranscriptionTestResult(available: false, message: "未知状态", duration: elapsed)
        }
    }

    /// 将逐词级别的 segments 合并为句子级字幕
    private func mergeIntoSentences(_ segments: [SubtitleSegment]) -> [SubtitleSegment] {
        guard !segments.isEmpty else { return [] }

        // 句尾标点
        let sentenceEnders: Set<Character> = ["。", "！", "？", "!", "?", ".", "；", ";", "\n"]
        // 逗号等短暂停顿
        let clauseEnders: Set<Character> = ["，", ",", "、", "：", ":", "—", "–"]

        var result: [SubtitleSegment] = []
        var currentText = ""
        var currentStart: TimeInterval = 0
        var currentEnd: TimeInterval = 0

        for seg in segments {
            let trimmed = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if currentText.isEmpty {
                currentStart = seg.start
            }
            currentText += trimmed
            currentEnd = seg.end

            let lastChar = trimmed.last ?? Character("")

            // 句号、问号、感叹号 → 强制断句
            if sentenceEnders.contains(lastChar) {
                result.append(SubtitleSegment(start: currentStart, end: currentEnd, text: currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
                currentText = ""
                continue
            }

            // 逗号等 → 如果累积文本够长（>15字），也断句
            if clauseEnders.contains(lastChar) && currentText.count >= 15 {
                result.append(SubtitleSegment(start: currentStart, end: currentEnd, text: currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
                currentText = ""
                continue
            }

            // 累积超过 25 个字 → 强制断句（防止字幕太长）
            if currentText.count >= 25 {
                result.append(SubtitleSegment(start: currentStart, end: currentEnd, text: currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
                currentText = ""
            }
        }

        // 剩余文本
        if !currentText.isEmpty {
            result.append(SubtitleSegment(start: currentStart, end: currentEnd, text: currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
        }

        return result
    }
}

// MARK: - 本地 Whisper (whisper.cpp)

final class WhisperCppProvider: TranscriptionProvider {
    private var modelPath: String
    private var whisperCLIPath: String

    init(model: WhisperModel = .tiny) {
        // whisper-cli：优先 app bundle 的 Frameworks，其次 Application Support，最后 brew
        let bundledCLI = Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/whisper-cli")
        if FileManager.default.fileExists(atPath: bundledCLI.path) {
            self.whisperCLIPath = bundledCLI.path
        } else {
            let appSupport = WhisperModelStore.directory.deletingLastPathComponent().appendingPathComponent("whisper-cli")
            if FileManager.default.fileExists(atPath: appSupport.path) {
                self.whisperCLIPath = appSupport.path
            } else {
                self.whisperCLIPath = "/opt/homebrew/opt/whisper-cpp/bin/whisper-cli"
            }
        }
        self.modelPath = WhisperModelStore.localPath(for: model).path
    }

    func transcribe(audioURL: URL, language: String) async throws -> [SubtitleSegment] {
        // 0. 确保 whisper-cli 可用（自动下载）
        try await ensureCLI()

        // 1. 转换为 WAV（whisper-cpp 需要 16kHz mono WAV）
        let wavURL = FileManager.default.temporaryDirectory.appendingPathComponent("subforge_whisper_\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: wavURL) }

        try await convertToWAV(input: audioURL, output: wavURL)

        // 2. 调用 whisper-cli
        let output = try await runWhisperCLI(wavURL: wavURL, language: language)

        // 3. 解析输出
        return parseWhisperOutput(output)
    }

    // MARK: - 确保 whisper-cli 可用

    private func ensureCLI() async throws {
        if FileManager.default.fileExists(atPath: whisperCLIPath) { return }
        throw TranscriptionError.cloudRequestFailedWithDetail("whisper-cli 未找到")
    }

    private func convertToWAV(input: URL, output: URL) async throws {
        // 用 macOS 自带的 afconvert（不需要 ffmpeg）
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        process.arguments = [
            "-f", "WAVE", "-d", "LEI16@16000", "-c", "1",
            input.path, output.path
        ]

        let pipe = Pipe()
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw TranscriptionError.cloudRequestFailedWithDetail("音频转换失败（afconvert）")
        }
    }

    private func runWhisperCLI(wavURL: URL, language: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: whisperCLIPath)
        process.arguments = [
            "-m", modelPath,
            "-f", wavURL.path,
            "-l", language.hasPrefix("zh") ? "zh" : language,
            "-t", "4",
            "--no-prints"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()  // 吞掉 stderr

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw TranscriptionError.cloudRequestFailedWithDetail("whisper-cli 执行失败")
        }

        return output
    }

    /// 解析 whisper-cli 的时间戳输出
    /// 格式: [00:00:00.000 --> 00:00:02.120]  文字内容
    private func parseWhisperOutput(_ output: String) -> [SubtitleSegment] {
        var segments: [SubtitleSegment] = []
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // 匹配时间戳格式 [HH:MM:SS.mmm --> HH:MM:SS.mmm]
            guard trimmed.hasPrefix("["),
                  let closeBracket = trimmed.firstIndex(of: "]") else { continue }

            let timeStr = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closeBracket])
            let parts = timeStr.components(separatedBy: "-->")
            guard parts.count == 2 else { continue }

            let start = parseWhisperTime(parts[0].trimmingCharacters(in: .whitespaces))
            let end = parseWhisperTime(parts[1].trimmingCharacters(in: .whitespaces))
            let text = String(trimmed[trimmed.index(after: closeBracket)...]).trimmingCharacters(in: .whitespaces)

            if !text.isEmpty {
                segments.append(SubtitleSegment(start: start, end: end, text: text))
            }
        }

        return segments
    }

    /// 解析 whisper 时间格式: 00:00:02.120
    private func parseWhisperTime(_ s: String) -> TimeInterval {
        let parts = s.components(separatedBy: ":")
        guard parts.count == 3,
              let h = Double(parts[0]),
              let m = Double(parts[1]),
              let sec = Double(parts[2]) else { return 0 }
        return h * 3600 + m * 60 + sec
    }

    func testAvailability() async -> TranscriptionTestResult {
        let fm = FileManager.default

        // 检查 whisper-cli
        guard fm.fileExists(atPath: whisperCLIPath) else {
            return TranscriptionTestResult(available: false, message: "whisper-cli 未安装，请在设置中下载", duration: nil)
        }

        // 检查模型
        guard fm.fileExists(atPath: modelPath) else {
            return TranscriptionTestResult(available: false, message: "模型未下载", duration: nil)
        }

        return TranscriptionTestResult(available: true, message: "可用", duration: nil)
    }
}

final class CloudASRProvider: TranscriptionProvider {
    private let apiURL: String
    private let apiKey: String
    private let model: String

    init(apiURL: String, apiKey: String, model: String = "whisper-1") {
        self.apiURL = apiURL
        self.apiKey = apiKey
        self.model = model
    }

    func transcribe(audioURL: URL, language: String) async throws -> [SubtitleSegment] {
        guard !apiURL.isEmpty else {
            throw TranscriptionError.cloudNotConfigured
        }

        // DashScope 异步 API
        if apiURL.contains("dashscope.aliyuncs.com") {
            return try await transcribeDashScope(audioURL: audioURL, language: language)
        }

        // 标准 Whisper 兼容 API（multipart）
        return try await transcribeWhisper(audioURL: audioURL, language: language)
    }

    // MARK: - DashScope 异步 API

    private func transcribeDashScope(audioURL: URL, language: String) async throws -> [SubtitleSegment] {
        // 1. 读取音频文件并编码为 base64
        let audioData = try Data(contentsOf: audioURL)
        let base64 = audioData.base64EncodedString()
        let ext = audioURL.pathExtension.lowercased()
        let mimeType = ext == "m4a" || ext == "mp4" ? "audio/mp4" : ext == "mp3" ? "audio/mpeg" : "audio/wav"
        let fileURL = "data:\(mimeType);base64,\(base64)"

        // 2. 提交任务
        let taskID = try await submitDashScopeTask(fileURL: fileURL, language: language)

        // 3. 轮询结果（返回 transcription_url）
        let resultURL = try await pollDashScopeTask(taskID: taskID)

        // 4. 下载并解析结果
        return try await downloadAndParseDashScopeResult(url: resultURL, audioURL: audioURL)
    }

    private func submitDashScopeTask(fileURL: String, language: String) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "input": [
                "file_url": fileURL
            ],
            "parameters": [
                "channel_id": [0],
                "enable_itn": true,
                "enable_words": true
            ]
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
            let body = String(data: data, encoding: .utf8) ?? ""
            throw TranscriptionError.cloudRequestFailedWithDetail("DashScope 提交失败 HTTP \(code): \(body.prefix(200))")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let output = json["output"] as? [String: Any],
              let taskID = output["task_id"] as? String else {
            throw TranscriptionError.cloudResponseInvalid
        }
        return taskID
    }

    /// 轮询任务，返回结果文件 URL
    private func pollDashScopeTask(taskID: String) async throws -> String {
        let pollURL = "https://dashscope.aliyuncs.com/api/v1/tasks/\(taskID)"
        var request = URLRequest(url: URL(string: pollURL)!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 300

        for _ in 0..<60 {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let output = json["output"] as? [String: Any],
                  let status = output["task_status"] as? String else {
                throw TranscriptionError.cloudResponseInvalid
            }

            switch status {
            case "SUCCEEDED":
                // 下载结果文件 URL
                if let result = output["result"] as? [String: String],
                   let url = result["transcription_url"] {
                    return url
                }
                throw TranscriptionError.cloudResponseInvalid
            case "FAILED":
                let msg = output["message"] as? String ?? "未知错误"
                throw TranscriptionError.cloudRequestFailedWithDetail("DashScope 任务失败：\(msg)")
            default:
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 秒
            }
        }

        throw TranscriptionError.timeout
    }

    /// 下载并解析 DashScope 结果文件
    private func downloadAndParseDashScopeResult(url: String, audioURL: URL) async throws -> [SubtitleSegment] {
        let (data, _) = try await URLSession.shared.data(from: URL(string: url)!)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranscriptionError.cloudResponseInvalid
        }

        // 尝试解析 sentences（带时间戳）
        if let transcripts = json["transcripts"] as? [[String: Any]],
           let first = transcripts.first,
           let sentences = first["sentences"] as? [[String: Any]] {
            let segments = sentences.compactMap { s -> SubtitleSegment? in
                guard let text = (s["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty else { return nil }
                let start = (s["begin_time"] as? Double ?? 0) / 1000.0
                let end = (s["end_time"] as? Double ?? 0) / 1000.0
                return SubtitleSegment(start: start, end: end > start ? end : start + 1, text: text)
            }
            if !segments.isEmpty { return segments }
        }

        // 回退：纯文本
        if let transcripts = json["transcripts"] as? [[String: Any]],
           let first = transcripts.first,
           let text = first["text"] as? String, !text.isEmpty {
            let duration = getAudioDuration(url: audioURL)
            return [SubtitleSegment(start: 0, end: duration, text: text)]
        }

        throw TranscriptionError.cloudResponseInvalid
    }

    // MARK: - 标准 Whisper 兼容 API（multipart）

    private func transcribeWhisper(audioURL: URL, language: String) async throws -> [SubtitleSegment] {
        let boundary = "----SubForge-\(UUID().uuidString)"
        var body = Data()

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(model)\r\n".data(using: .utf8)!)

        let langCode = language.hasPrefix("zh") ? "zh" : language
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(langCode)\r\n".data(using: .utf8)!)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("verbose_json\r\n".data(using: .utf8)!)

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
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.cloudRequestFailed
        }
        if httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "未知错误"
            throw TranscriptionError.cloudRequestFailedWithDetail("HTTP \(httpResponse.statusCode): \(body.prefix(200))")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranscriptionError.cloudResponseInvalid
        }

        if let segmentsData = json["segments"] as? [[String: Any]] {
            return segmentsData.compactMap { dict -> SubtitleSegment? in
                guard let start = dict["start"] as? Double,
                      let end = dict["end"] as? Double,
                      let text = (dict["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty else { return nil }
                return SubtitleSegment(start: start, end: end, text: text)
            }
        }

        if let text = json["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let duration = getAudioDuration(url: audioURL)
            return [SubtitleSegment(start: 0, end: duration, text: text.trimmingCharacters(in: .whitespacesAndNewlines))]
        }

        throw TranscriptionError.cloudResponseInvalid
    }

    private func getAudioDuration(url: URL) -> TimeInterval {
        let asset = AVURLAsset(url: url)
        let duration = asset.duration
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isNaN ? 10.0 : seconds
    }

    func testAvailability() async -> TranscriptionTestResult {
        guard !apiURL.isEmpty, !apiKey.isEmpty else {
            return TranscriptionTestResult(available: false, message: "未配置 API 地址或 Key", duration: nil)
        }
        guard let url = URL(string: apiURL) else {
            return TranscriptionTestResult(available: false, message: "API 地址格式错误", duration: nil)
        }
        let start = Date()
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 10
            let (_, response) = try await URLSession.shared.data(for: request)
            let elapsed = Date().timeIntervalSince(start)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode < 500 {
                return TranscriptionTestResult(available: true, message: "服务可达，延迟 \(String(format: "%.1f", elapsed * 1000))ms", duration: elapsed)
            } else {
                return TranscriptionTestResult(available: false, message: "服务返回错误", duration: elapsed)
            }
        } catch {
            let elapsed = Date().timeIntervalSince(start)
            return TranscriptionTestResult(available: false, message: "连接失败：\(error.localizedDescription)", duration: elapsed)
        }
    }
}

enum TranscriptionError: LocalizedError {
    case notAuthorized(SFSpeechRecognizerAuthorizationStatus)
    case recognizerUnavailable(String)
    case cloudNotConfigured
    case cloudRequestFailed
    case cloudRequestFailedWithDetail(String)
    case cloudResponseInvalid
    case timeout

    var errorDescription: String? {
        switch self {
        case .notAuthorized(let status):
            return "语音识别未授权（状态: \(status.rawValue)）"
        case .recognizerUnavailable(let lang):
            return "语言 \(lang) 的识别器不可用"
        case .cloudNotConfigured:
            return "云端 ASR 未配置，请在设置中填写 API 地址和 Key"
        case .cloudRequestFailed:
            return "云端 ASR 请求失败"
        case .cloudRequestFailedWithDetail(let detail):
            return "云端 ASR 错误：\(detail)"
        case .cloudResponseInvalid:
            return "云端 ASR 响应格式异常"
        case .timeout:
            return "转写超时（5分钟）"
        }
    }
}

/// 工厂：根据设置创建转写 provider
enum TranscriptionService {
    static func createProvider(settings: AppSettings) -> TranscriptionProvider {
        switch settings.transcriptionEngine {
        case .whisperLocal:
            return WhisperCppProvider(model: settings.whisperModel)
        case .appleSpeech:
            return AppleSpeechProvider()
        case .cloudASR:
            return CloudASRProvider(apiURL: settings.effectiveASRURL, apiKey: settings.cloudASRKey, model: settings.effectiveASRModel)
        }
    }
}
