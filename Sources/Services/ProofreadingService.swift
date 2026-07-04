import Foundation

protocol ProofreadingProvider {
    func proofread(
        segments: [SubtitleSegment],
        batchSize: Int,
        prompt: String,
        strictCorrections: Bool
    ) async throws -> [SubtitleSegment]
}

final class CloudLLMProvider: ProofreadingProvider {
    private let apiURL: String
    private let apiKey: String
    private let model: String

    init(apiURL: String, apiKey: String, model: String) {
        self.apiURL = apiURL
        self.apiKey = apiKey
        self.model = model
    }

    func proofread(
        segments: [SubtitleSegment],
        batchSize: Int = 20,
        prompt: String,
        strictCorrections: Bool
    ) async throws -> [SubtitleSegment] {
        guard !apiURL.isEmpty, !apiKey.isEmpty else {
            throw ProofreadingError.notConfigured
        }

        let startedAt = Date()
        var allCorrected: [SubtitleSegment] = []
        let batches = makeBatches(
            segments,
            maxLineCount: max(1, batchSize),
            maxCharacterCount: 2200
        )

        AppLog.proofreading.info(
            "proofreadStart segments=\(segments.count, privacy: .public) batches=\(batches.count, privacy: .public) lineLimit=\(max(1, batchSize), privacy: .public)"
        )

        for (index, batch) in batches.enumerated() {
            let batchStartedAt = Date()
            let corrected = try await proofreadBatch(batch, prompt: prompt, strictCorrections: strictCorrections)
            allCorrected.append(contentsOf: corrected)
            AppLog.proofreading.info(
                "proofreadBatchDone index=\(index + 1, privacy: .public)/\(batches.count, privacy: .public) lines=\(batch.count, privacy: .public) elapsed=\(Date().timeIntervalSince(batchStartedAt), privacy: .public)"
            )
        }

        AppLog.proofreading.info(
            "proofreadDone segments=\(allCorrected.count, privacy: .public) elapsed=\(Date().timeIntervalSince(startedAt), privacy: .public)"
        )

        return allCorrected
    }

    private func makeBatches(
        _ segments: [SubtitleSegment],
        maxLineCount: Int,
        maxCharacterCount: Int
    ) -> [[SubtitleSegment]] {
        guard !segments.isEmpty else { return [] }

        var batches: [[SubtitleSegment]] = []
        var currentBatch: [SubtitleSegment] = []
        var currentCharacterCount = 0

        for segment in segments {
            let estimatedCharacters = max(segment.text.count + 8, 1)
            let exceedsLineLimit = currentBatch.count >= maxLineCount
            let exceedsCharacterLimit = !currentBatch.isEmpty && currentCharacterCount + estimatedCharacters > maxCharacterCount

            if exceedsLineLimit || exceedsCharacterLimit {
                batches.append(currentBatch)
                currentBatch = []
                currentCharacterCount = 0
            }

            currentBatch.append(segment)
            currentCharacterCount += estimatedCharacters
        }

        if !currentBatch.isEmpty {
            batches.append(currentBatch)
        }

        return batches
    }

    private func proofreadBatch(
        _ segments: [SubtitleSegment],
        prompt: String,
        strictCorrections: Bool
    ) async throws -> [SubtitleSegment] {
        let inputLines = segments.enumerated().map { index, segment in
            "\(index + 1). \(segment.text)"
        }.joined(separator: "\n")

        let correctionRules = strictCorrections
            ? "优先修正错别字、漏字、标点和显著识别错误，不做风格润色。"
            : "优先修正错别字、漏字、标点和显著识别错误，可做极轻微顺句，但不能改写原意。"

        let composedPrompt = """
        你是字幕校对专家。

        核心要求：
        1. \(correctionRules)
        2. 输出总行数必须和输入完全相同。
        3. 每行保留原始序号，不跳号。
        4. 不允许合并、删除、拆分任意字幕行。
        5. 每一行都必须输出非空文本。
        6. 字幕行末不补句号、逗号、顿号、分号或冒号；问号、叹号、省略号只有表达语气时才保留。
        7. 只输出“序号 + 文本”，不要解释。

        额外提示：
        \(prompt)

        需要校对的字幕：
        \(inputLines)
        """

        let body: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "system",
                    "content": "你是字幕校对助手，只输出修正后的字幕，每行一条，保持序号格式。遵守字幕标点风格，不要输出其他内容。"
                ],
                [
                    "role": "user",
                    "content": composedPrompt
                ]
            ],
            "temperature": 0.1,
            "max_tokens": 4096
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ProofreadingError.apiError("HTTP \(code)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw ProofreadingError.invalidResponse
        }

        let correctedLines = parseResponse(content, expectedCount: segments.count)
        var results: [SubtitleSegment] = []

        for (index, segment) in segments.enumerated() {
            var corrected = segment
            let normalizedText = normalizeSubtitlePunctuation(correctedLines[index])
            corrected.text = normalizedText.isEmpty ? segment.text : normalizedText

            results.append(corrected)
        }

        return results
    }

    private func parseResponse(_ content: String, expectedCount: Int) -> [String] {
        var result = [String](repeating: "", count: expectedCount)
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        for line in lines where !line.isEmpty {
            var matchedIndex: Int?
            var text = line

            if let range = line.range(of: #"^\d+[.、]\s*"#, options: .regularExpression) {
                let numberString = line[line.startIndex..<range.upperBound]
                    .trimmingCharacters(in: CharacterSet(charactersIn: ".、 "))
                if let number = Int(numberString), number >= 1, number <= expectedCount {
                    matchedIndex = number - 1
                    text = String(line[range.upperBound...])
                }
            }

            if matchedIndex == nil {
                matchedIndex = result.firstIndex(of: "")
            }

            if let index = matchedIndex, index < expectedCount {
                result[index] = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return result
    }

    private func normalizeSubtitlePunctuation(_ text: String) -> String {
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let removableLineEndPunctuation: Set<Character> = ["。", "．", ".", "，", ",", "、", "；", ";", "：", ":"]

        while let last = normalized.last, removableLineEndPunctuation.contains(last) {
            normalized.removeLast()
            normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return normalized
    }
}

enum ProofreadingError: LocalizedError {
    case notConfigured
    case apiError(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "模型纠正未配置，请填写 Base URL、Key 和模型名"
        case .apiError(let message):
            "模型纠正请求失败：\(message)"
        case .invalidResponse:
            "模型纠正响应格式异常"
        }
    }
}

enum ProofreadingService {
    static func createProvider(settings: AppSettings) -> ProofreadingProvider? {
        var resolvedSettings = settings
        guard resolvedSettings.proofreadingEnabled else { return nil }

        switch resolvedSettings.proofreadingEngine {
        case .cloudLLM:
            SettingsStore.hydrateSecrets(into: &resolvedSettings, includeASR: false, includeLLM: true)
            return CloudLLMProvider(
                apiURL: resolvedSettings.effectiveLLMURL,
                apiKey: resolvedSettings.cloudLLMKey,
                model: resolvedSettings.effectiveLLMModel
            )
        case .appleLocal:
            return nil
        }
    }
}
