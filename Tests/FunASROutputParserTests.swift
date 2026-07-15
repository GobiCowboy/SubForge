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
