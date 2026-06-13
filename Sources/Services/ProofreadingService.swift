import Foundation

/// 校对服务统一协议
protocol ProofreadingProvider {
    func proofread(segments: [SubtitleSegment], batchSize: Int) async throws -> [SubtitleSegment]
    func testAvailability() async -> (available: Bool, message: String)
}

/// 云端 LLM 校对实现（OpenAI Chat API 兼容）
final class CloudLLMProvider: ProofreadingProvider {
    private let apiURL: String
    private let apiKey: String
    private let model: String

    init(apiURL: String, apiKey: String, model: String = "deepseek-chat") {
        self.apiURL = apiURL
        self.apiKey = apiKey
        self.model = model
    }

    func proofread(segments: [SubtitleSegment], batchSize: Int = 20) async throws -> [SubtitleSegment] {
        guard !apiURL.isEmpty, !apiKey.isEmpty else {
            throw ProofreadingError.notConfigured
        }

        var allCorrected: [SubtitleSegment] = []

        // 分批处理
        let batches = stride(from: 0, to: segments.count, by: batchSize).map {
            Array(segments[$0..<min($0 + batchSize, segments.count)])
        }

        for batch in batches {
            let corrected = try await proofreadBatch(batch)
            allCorrected.append(contentsOf: corrected)
        }

        return allCorrected
    }

    private func proofreadBatch(_ segments: [SubtitleSegment]) async throws -> [SubtitleSegment] {
        // 构建输入文本（只带序号，不带时间戳）
        let inputLines = segments.enumerated().map { idx, seg in
            "\(idx + 1). \(seg.text)"
        }.joined(separator: "\n")

        let prompt = """
        你是字幕校对专家。修正错别字、漏字、ASR识别错误。

        规则：
        1. 修正文字错误，不改变原意
        2. 太短的行（如"文件""句号"等碎片）合并到相邻行
        3. 合并时文字放到序号小的那行，被合并行只写序号不留文字
        4. 输出总行数必须和输入完全相同
        5. 每行保留原始序号，不跳号
        6. 没错误的行原样输出
        7. 只输出序号和文字，不加说明

        示例：
        1. 这是一个Markdown
        2. 文件
        3. 可以用来做笔记

        输出：
        1. 这是一个Markdown文件
        2.
        3. 可以用来做笔记

        需要校对的字幕：
        \(inputLines)
        """

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "你是字幕校对助手，只输出修正后的字幕，每行一条，保持序号格式。不要输出其他内容。"],
                ["role": "user", "content": prompt]
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

        // 解析 OpenAI Chat API 响应
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ProofreadingError.invalidResponse
        }

        // 解析修正后的文本
        let correctedLines = parseResponse(content, expectedCount: segments.count)

        // 构建修正后的 segments，处理合并的时间戳
        var result: [SubtitleSegment] = []
        for (idx, seg) in segments.enumerated() {
            var corrected = seg
            corrected.text = correctedLines[idx]

            // 如果当前行为空（被合并），把时间范围并入前一条非空行
            if corrected.text.isEmpty, !result.isEmpty {
                // 找到前一条非空行
                for j in stride(from: result.count - 1, through: 0, by: -1) {
                    if !result[j].text.isEmpty {
                        result[j].end = seg.end  // 延长前一条的结束时间
                        break
                    }
                }
            }

            result.append(corrected)
        }

        return result
    }

    /// 解析 LLM 响应，提取每行修正后的文本（保留空行 = 被合并的行）
    private func parseResponse(_ content: String, expectedCount: Int) -> [String] {
        // 初始化结果数组，全部为空
        var result = [String](repeating: "", count: expectedCount)

        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        for line in lines {
            guard !line.isEmpty else { continue }

            // 提取序号："1. xxx" → index=0, text="xxx"
            // 也处理 "1.xxx" 和 "1、xxx" 格式
            var idx: Int?
            var text = line

            // 尝试匹配 "数字. " 或 "数字、" 前缀
            if let dotRange = line.range(of: #"^\d+[.、]\s*"#, options: .regularExpression) {
                let numStr = line[line.startIndex..<dotRange.upperBound]
                    .trimmingCharacters(in: CharacterSet(charactersIn: ".、 "))
                if let num = Int(numStr), num >= 1, num <= expectedCount {
                    idx = num - 1  // 转为 0-based
                    text = String(line[dotRange.upperBound...])
                }
            }

            // 如果没匹配到序号，按顺序填入下一个空位
            if idx == nil {
                idx = result.firstIndex(of: "")
            }

            if let i = idx, i < expectedCount {
                result[i] = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return result
    }

    func testAvailability() async -> (available: Bool, message: String) {
        guard !apiURL.isEmpty, !apiKey.isEmpty else {
            return (false, "请填写 API 地址和 Key")
        }

        // 发一个最简单的请求测试连通性
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": "你好，请回复校对可用四个字。"]
            ],
            "max_tokens": 20
        ]

        do {
            let bodyData = try JSONSerialization.data(withJSONObject: body)
            var request = URLRequest(url: URL(string: apiURL)!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.httpBody = bodyData
            request.timeoutInterval = 30

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return (false, "无响应")
            }

            if httpResponse.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let first = choices.first,
                   let message = first["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    return (true, "可用：\(content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))")
                }
                return (true, "连接成功（\(model)）")
            } else {
                let body = String(data: data, encoding: .utf8) ?? ""
                return (false, "HTTP \(httpResponse.statusCode): \(body.prefix(80))")
            }
        } catch {
            return (false, "连接失败：\(error.localizedDescription)")
        }
    }
}

enum ProofreadingError: LocalizedError {
    case notConfigured
    case apiError(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "云端 LLM 未配置"
        case .apiError(let msg):
            return "API 错误：\(msg)"
        case .invalidResponse:
            return "响应格式异常"
        }
    }
}

/// 工厂：根据设置创建校对 provider
enum ProofreadingService {
    static func createProvider(settings: AppSettings) -> ProofreadingProvider? {
        guard settings.proofreadingEnabled else { return nil }
        switch settings.proofreadingEngine {
        case .cloudLLM:
            return CloudLLMProvider(
                apiURL: settings.effectiveLLMURL,
                apiKey: settings.cloudLLMKey,
                model: settings.effectiveLLMModel
            )
        case .appleLocal:
            // TODO: Apple Foundation Models 实现
            return nil
        }
    }
}
