import AVFoundation
import Foundation
import Speech

extension CloudASRProvider {
    func pollDashScopeTask(taskID: String) async throws -> String {
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

    func dashScopeTaskPollingURL(taskID: String) -> URL? {
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

    func dashScopeASROptions(language: String) -> [String: Any] {
        var options: [String: Any] = ["enable_itn": true]
        if let normalized = normalizeDashScopeLanguage(language) {
            options["language"] = normalized
        }
        return options
    }

    func dashScopeTaskParameters(language: String) -> [String: Any] {
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

    func normalizeDashScopeLanguage(_ language: String) -> String? {
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

    func approximateSegments(from text: String, duration: TimeInterval) -> [SubtitleSegment] {
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
}
