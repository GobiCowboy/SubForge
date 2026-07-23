import AVFoundation
import Foundation
import Speech

extension CloudASRProvider {
    func downloadDashScopeResult(url: String, audioURL: URL) async throws -> [SubtitleSegment] {
        guard let resolvedURL = resolvedDashScopeResultURL(from: url) else {
            throw TranscriptionError.cloudResponseInvalid
        }

        let (data, _) = try await URLSession.shared.data(from: resolvedURL)
        let parsed = try DashScopeTranscriptionParser.parse(data)

        if !parsed.words.isEmpty {
            return TimedSubtitleSegmenter.segment(
                parsed.words,
                configuration: segmentationConfiguration
            )
        }

        if !parsed.sentences.isEmpty {
            AppLog.transcription.warning("cloudASR result has sentence timestamps only; using estimated word timing")
            return TimedSubtitleSegmenter.segmentEstimated(
                parsed.sentences,
                configuration: segmentationConfiguration
            )
        }

        if !parsed.text.isEmpty {
            let duration = await audioDuration(url: audioURL)
            AppLog.transcription.warning("cloudASR result has no timestamps; using full-audio estimation")
            return TimedSubtitleSegmenter.segmentEstimated(
                approximateSegments(from: parsed.text, duration: duration),
                configuration: segmentationConfiguration
            )
        }

        throw TranscriptionError.cloudResponseInvalid
    }

    func resolvedDashScopeResultURL(from rawURL: String) -> URL? {
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

    func transcribeWhisperCompatible(audioURL: URL, language: String) async throws -> [SubtitleSegment] {
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
        appendField("timestamp_granularities[]", value: "word")

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

        if let wordsData = json["words"] as? [[String: Any]] {
            let words = wordsData.compactMap { dict -> SubtitleWord? in
                let token = (dict["word"] as? String) ?? (dict["text"] as? String)
                guard let token,
                      let start = Self.doubleValue(dict["start"]),
                      let end = Self.doubleValue(dict["end"]),
                      !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }
                return SubtitleWord(start: start, end: max(end, start + 0.01), text: token)
            }
            if !words.isEmpty {
                return TimedSubtitleSegmenter.segment(words, configuration: segmentationConfiguration)
            }
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

    func audioDuration(url: URL) async -> TimeInterval {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            return seconds.isNaN ? 10.0 : seconds
        } catch {
            return 10.0
        }
    }

    static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            number.doubleValue
        case let text as String:
            Double(text)
        default:
            nil
        }
    }
}
