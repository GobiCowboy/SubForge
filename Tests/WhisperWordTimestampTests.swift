import Foundation
import Testing
@testable import SubForge

@Test func parsesWhisperWordTimestamps() throws {
    let json = """
    {
      "systeminfo": "WHISPER | MTL : EMBED_LIBRARY = 1 |",
      "transcription": [{
        "offsets": {"from": 0, "to": 1200},
        "text": "你好世界",
        "tokens": [
          {"text": "[_BEG_]", "offsets": {"from": 0, "to": 0}, "t_dtw": -1},
          {"text": "你好", "offsets": {"from": 100, "to": 500}, "t_dtw": 20},
          {"text": "世界", "offsets": {"from": 600, "to": 1100}, "t_dtw": 70}
        ]
      }]
    }
    """

    let result = try WhisperJSONParser.parse(Data(json.utf8))

    #expect(result.metalAvailable)
    #expect(result.dtwAligned)
    #expect(result.segments.count == 1)
    #expect(result.segments[0].start == 0.2)
    #expect(result.segments[0].end == 1.2)
    #expect(result.segments[0].words?.count == 2)
    #expect(result.segments[0].words?[0].end == 0.7)
}

@Test func segmentationUsesRealWordBoundaries() {
    let segment = SubtitleSegment(
        start: 0,
        end: 8,
        text: "这是第一句话。这是第二句话，而且需要拆分。",
        words: [
            SubtitleWord(start: 0.2, end: 0.8, text: "这是"),
            SubtitleWord(start: 0.8, end: 1.5, text: "第一句话。"),
            SubtitleWord(start: 3.0, end: 3.6, text: "这是"),
            SubtitleWord(start: 3.6, end: 4.4, text: "第二句话，"),
            SubtitleWord(start: 4.4, end: 5.0, text: "而且"),
            SubtitleWord(start: 5.0, end: 6.2, text: "需要拆分。")
        ]
    )

    let refined = SubtitleSegmentationService.refine([segment])

    #expect(refined.count == 2)
    #expect(refined[0].start == 0.2)
    #expect(refined[0].end == 1.5)
    #expect(refined[1].start == 3.0)
    #expect(refined[1].end == 6.2)
}

@Test func decodesProjectsCreatedBeforeWordTimestamps() throws {
    let id = UUID()
    let json = """
    {"id":"\(id.uuidString)","start":1,"end":2,"text":"旧字幕"}
    """

    let segment = try JSONDecoder().decode(SubtitleSegment.self, from: Data(json.utf8))
    #expect(segment.words == nil)
}

@Test func sharedSegmenterKeepsEnglishWordsAndUsesPunctuation() {
    let words = [
        SubtitleWord(start: 0.0, end: 0.4, text: "这是"),
        SubtitleWord(start: 0.4, end: 0.8, text: "一句话。"),
        SubtitleWord(start: 1.0, end: 1.4, text: "Final"),
        SubtitleWord(start: 1.4, end: 1.8, text: "Cut"),
        SubtitleWord(start: 1.8, end: 2.2, text: "Pro"),
        SubtitleWord(start: 2.2, end: 2.6, text: "很好用。")
    ]

    let segments = TimedSubtitleSegmenter.segment(
        words,
        configuration: SubtitleSegmentationConfiguration(maxCharacters: 12)
    )

    #expect(segments.map(\.text) == ["这是一句话。", "Final Cut Pro", "很好用。"])
    #expect(!segments.map(\.text).joined(separator: "|").contains("Final Cut|Pro"))
}

@Test func sharedSegmenterRemovesTimestampOverlap() {
    let words = [
        SubtitleWord(start: 0.0, end: 2.0, text: "第一句。"),
        SubtitleWord(start: 1.8, end: 3.0, text: "第二句。")
    ]

    let segments = TimedSubtitleSegmenter.segment(
        words,
        configuration: SubtitleSegmentationConfiguration(maxCharacters: 24)
    )

    #expect(segments.count == 2)
    #expect(segments[0].end == segments[1].start)
}

@Test func whisperParserMergesEnglishBPEPieces() throws {
    let json = """
    {
      "systeminfo": "WHISPER | MTL : EMBED_LIBRARY = 1 |",
      "transcription": [{
        "offsets": {"from": 0, "to": 1200},
        "text": "Final Cut Pro",
        "tokens": [
          {"text": " Final", "offsets": {"from": 0, "to": 300}, "t_dtw": 0},
          {"text": " Cu", "offsets": {"from": 300, "to": 600}, "t_dtw": 30},
          {"text": "t", "offsets": {"from": 600, "to": 700}, "t_dtw": 60},
          {"text": " Pro", "offsets": {"from": 700, "to": 1200}, "t_dtw": 70}
        ]
      }]
    }
    """

    let result = try WhisperJSONParser.parse(Data(json.utf8))
    #expect(result.segments[0].words?.map { $0.text.trimmingCharacters(in: .whitespaces) } == ["Final", "Cut", "Pro"])
}

@Test func estimatedFallbackAlsoHonorsGlobalLength() {
    let source = SubtitleSegment(
        start: 0,
        end: 6,
        text: "这是云端整段文本，Final Cut Pro 不应该拆开英文单词。"
    )

    let segments = TimedSubtitleSegmenter.segmentEstimated(
        [source],
        configuration: SubtitleSegmentationConfiguration(maxCharacters: 14)
    )

    #expect(segments.map(\.text).joined().contains("Final Cut Pro"))
    #expect(!segments.map(\.text).joined(separator: "|").contains("Final Cut|Pro"))
}

@Test func estimatedFallbackUsesChineseWordBoundariesInsteadOfHardCharacters() {
    let source = SubtitleSegment(
        start: 0,
        end: 12,
        text: "如果你使用Final Cut Pro制作非英文视频你会发现真正麻烦的是整个字幕工作流很多时候你需要从"
    )

    let segments = TimedSubtitleSegmenter.segmentEstimated(
        [source],
        configuration: SubtitleSegmentationConfiguration(maxCharacters: 26)
    )
    let separated = segments.map(\.text).joined(separator: "|")

    #expect(!separated.contains("Final Cut|Pro"))
    #expect(!separated.contains("字幕工|作流"))
    #expect(!separated.contains("你|会发现"))
    #expect(!separated.contains("需要|从"))
}

@Test func cloudEndpointValidationRejectsPlaceholderInsteadOfCrashing() {
    #expect(CloudASRProvider.validatedEndpoint("https://{WorkspaceId}.example.com/v1") == nil)
    #expect(CloudASRProvider.validatedEndpoint("not a URL") == nil)
    #expect(CloudASRProvider.validatedEndpoint("https://example.com/v1") != nil)
}

@Test func appleSpeechLongPauseDoesNotStretchShortSubtitle() {
    let end = AppleSpeechProvider.normalizedSegmentEnd(
        start: 15.48,
        duration: 16.68,
        characterCount: 3,
        nextStart: 32.16
    )

    #expect(end == 17.43)
}
