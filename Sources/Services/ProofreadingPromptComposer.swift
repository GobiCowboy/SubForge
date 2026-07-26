import Foundation

enum HotwordInputParser {
    static func parse(_ input: String) -> [String] {
        var seen: Set<String> = []
        return input
            .components(separatedBy: CharacterSet(charactersIn: "\n,，"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    static func merging(_ groups: [String]...) -> [String] {
        var seen: Set<String> = []
        return groups
            .flatMap { $0 }
            .filter { seen.insert($0).inserted }
    }
}

enum ProofreadingPromptComposer {
    static func userPrompt(basePrompt: String, hotwords: [String]) -> String {
        let base = basePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hotwords.isEmpty else { return base }
        let list = hotwords.map { "- \($0)" }.joined(separator: "\n")
        let hotwordRules = """
        本次视频中经常出现以下专有名词：

        \(list)

        请结合上下文判断识别错误，并统一使用上面的正确写法。
        热词严格区分大小写、空格和符号；清单中的写法就是唯一正确写法，输出时必须原样保留。
        不要把热词自动改成全大写、全小写或首字母大写，也不要把大小写不同的写法视为等价。
        用户不会提供错误变体，请自行判断。
        """
        return [base, hotwordRules].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}

enum ProofreadingResponseParser {
    static func parse(_ content: String, expectedCount: Int) throws -> [String] {
        guard expectedCount > 0 else { return [] }
        var result: [Int: String] = [:]
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines {
            guard let range = line.range(of: #"^(\d+)[.、]\s*"#, options: .regularExpression),
                  range.lowerBound == line.startIndex else {
                throw ProofreadingError.invalidResponse
            }
            let prefix = String(line[..<range.upperBound])
            guard let numberRange = prefix.range(of: #"\d+"#, options: .regularExpression),
                  let number = Int(prefix[numberRange]),
                  (1...expectedCount).contains(number),
                  result[number] == nil else {
                throw ProofreadingError.invalidResponse
            }
            let text = String(line[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw ProofreadingError.invalidResponse
            }
            result[number] = text
        }

        guard result.count == expectedCount else {
            throw ProofreadingError.invalidResponse
        }
        return try (1...expectedCount).map { number in
            guard let text = result[number] else {
                throw ProofreadingError.invalidResponse
            }
            return text
        }
    }
}
