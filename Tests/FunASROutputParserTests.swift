import Foundation
import Testing
@testable import SubForge

@Test func funASRParserStripsMetaTagsAndEstimatesDuration() {
    let stdout = "<|zh|><|NEUTRAL|><|Speech|><|woitn|>你好世界，这是测试。"
    let segments = FunASROutputParser.parse(stdout: stdout, audioDuration: 4.0)

    #expect(segments.count == 1)
    #expect(segments[0].start == 0)
    #expect(segments[0].end == 4.0)
    #expect(segments[0].text.contains("你好世界"))
    #expect(!segments[0].text.contains("<|"))
}


@Test func funASRParserAcceptsTimedLinesWhenPresent() {
    let stdout = """
    [0.0-1.2] 第一句
    [1.5-2.8] 第二句
    """
    let segments = FunASROutputParser.parse(stdout: stdout, audioDuration: 10)

    #expect(segments.count == 2)
    #expect(segments[0].start == 0.0)
    #expect(segments[0].end == 1.2)
    #expect(segments[0].text == "第一句")
    #expect(segments[1].text == "第二句")
}

@Test func funASRLanguageIsAutoOnlyInProviderContract() {
    // CLI 无 language 参数；映射仅作文档/后续扩展占位。
    #expect(FunASRModel.sensevoiceSmallQ8.fileName == "sensevoice-small-q8.gguf")
    #expect(FunASRModelStore.vadFileName == "fsmn-vad.gguf")
}

@Test func funASRVADParserReadsMillisecondPairs() {
    let intervals = FunASRVADParser.parse(stdout: "0 2000\n5000 9000\n", fullDuration: 12)
    #expect(intervals.count == 2)
    #expect(intervals[0].start == 0)
    #expect(intervals[0].end == 2.0)
    #expect(intervals[1].start == 5.0)
    #expect(intervals[1].end == 9.0)
}

@Test func stripTrailingPunctuationKeepsQuestionAndExclamation() {
    #expect(SubtitleTextFormatting.stripTrailingLineEndPunctuation("你好。") == "你好")
    #expect(SubtitleTextFormatting.stripTrailingLineEndPunctuation("你好。。") == "你好")
    #expect(SubtitleTextFormatting.stripTrailingLineEndPunctuation("真的吗？") == "真的吗？")
    #expect(SubtitleTextFormatting.stripTrailingLineEndPunctuation("太棒了！") == "太棒了！")
    #expect(SubtitleTextFormatting.stripTrailingLineEndPunctuation("什么？。") == "什么？")
}

@Test func funASRTimingMapperSkipsLeadingSilenceViaVAD() {
    let text = "第一句内容。第二句内容。"
    let intervals = [
        FunASRVADInterval(start: 5.0, end: 8.0),
        FunASRVADInterval(start: 10.0, end: 14.0)
    ]
    let coarse = FunASRTimingMapper.coarseSegments(
        text: text,
        intervals: intervals,
        fullDuration: 20
    )
    #expect(!coarse.isEmpty)
    #expect(coarse.first!.start >= 4.9)
    #expect(coarse.first!.start < 6.0)

    let refined = TimedSubtitleSegmenter.segmentEstimated(
        coarse,
        configuration: SubtitleSegmentationConfiguration(maxCharacters: 24)
    )
    #expect(!refined.isEmpty)
    #expect(refined.first!.start >= 4.9)
}
