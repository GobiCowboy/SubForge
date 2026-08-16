import Foundation
import Testing
@testable import SubForge

@Test func dashScopeParserUsesWordsAcrossAllTranscripts() throws {
    let json = """
    {
      "transcripts": [
        {"sentences": [{"begin_time": 100, "end_time": 900, "text": "你好，世界", "words": [
          {"begin_time": 100, "end_time": 360, "text": "你好", "punctuation": "，"},
          {"begin_time": 520, "end_time": 900, "text": "世界"}
        ]}]},
        {"sentences": [{"begin_time": 1200, "end_time": 1700, "text": "第二句", "words": [
          {"begin_time": 1200, "end_time": 1700, "text": "第二句"}
        ]}]}
      ]
    }
    """

    let parsed = try DashScopeTranscriptionParser.parse(Data(json.utf8))

    #expect(parsed.words.map(\.text) == ["你好，", "世界", "第二句"])
    #expect(parsed.words.map(\.start) == [0.1, 0.52, 1.2])
    #expect(parsed.sentences.map(\.text) == ["你好，世界", "第二句"])
    #expect(parsed.sentences.map { $0.words?.count } == [2, 1])
}
