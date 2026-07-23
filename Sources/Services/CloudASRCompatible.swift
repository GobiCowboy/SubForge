import AVFoundation
import Foundation
import Speech

extension CloudASRProvider {
    func transcribeDashScopeCompatible(audioURL: URL, language: String) async throws -> [SubtitleSegment] {
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

    func transcribeDashScopeAsync(audioURL: URL, language: String) async throws -> [SubtitleSegment] {
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
}
