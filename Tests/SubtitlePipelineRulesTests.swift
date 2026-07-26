import Foundation
import Testing
@testable import SubForge

@Test func effectiveLengthIgnoresPunctuationWhitespaceAndFillers() {
    #expect(SubtitleEffectiveLength.count("粘贴，哎？") == 2)
    #expect(SubtitleEffectiveLength.count("一般来说呢，") == 4)
    #expect(SubtitleEffectiveLength.count("好，下面开始") == 4)
    #expect(SubtitleEffectiveLength.count("这个很好用") == 5)
    #expect(SubtitleEffectiveLength.count("Final Cut Pro！") == 11)
}

@Test func primaryPunctuationSplitsAndShortFillerMergesForward() {
    let source = SubtitleSegment(
        start: 0,
        end: 5,
        text: "一般来说呢，呃，添加字幕是整个视频的收尾阶段。",
        words: [
            SubtitleWord(start: 0.0, end: 1.0, text: "一般来说呢，"),
            SubtitleWord(start: 1.1, end: 1.3, text: "呃，"),
            SubtitleWord(start: 1.4, end: 5.0, text: "添加字幕是整个视频的收尾阶段。")
        ]
    )

    let output = TimedSubtitleSegmenter.segmentSources(
        [source],
        configuration: .init(maxCharacters: 32)
    )

    #expect(output.map(\.text) == [
        "一般来说呢，",
        "呃，添加字幕是整个视频的收尾阶段。"
    ])
}

@Test func fallbackPunctuationOnlySplitsAnOverlongPrimaryChunk() {
    let shortSource = SubtitleSegment(start: 0, end: 2, text: "苹果、香蕉、橙子")
    let longSource = SubtitleSegment(
        start: 3,
        end: 8,
        text: "这是很长的前半段、这是后面的内容还比较长。"
    )
    let configuration = SubtitleSegmentationConfiguration(maxCharacters: 10)

    let shortOutput = TimedSubtitleSegmenter.segmentSources(
        [shortSource],
        configuration: configuration
    )
    let longOutput = TimedSubtitleSegmenter.segmentSources(
        [longSource],
        configuration: configuration
    )

    #expect(shortOutput.map(\.text) == ["苹果、香蕉、橙子"])
    #expect(longOutput.first?.text == "这是很长的前半段、")
    #expect(longOutput.count > 1)
    #expect(longOutput.allSatisfy {
        SubtitleEffectiveLength.count($0.text) <= configuration.maxCharacters
    })
}

@Test func shortChunksNeverMergeAcrossSourceSegments() {
    let sources = [
        SubtitleSegment(start: 0, end: 1, text: "好，"),
        SubtitleSegment(start: 2, end: 3, text: "开始。")
    ]

    let output = TimedSubtitleSegmenter.segmentSources(
        sources,
        configuration: .init(maxCharacters: 32)
    )

    #expect(output.count == 2)
    #expect(output.map(\.text) == ["好，", "开始。"])
}

@Test func punctuationPolicyReplacesOnlyUnselectedGroupsWithSpaces() {
    let input = "他说：“Final Cut Pro……真的好用吗？”——当然！"
    let retained: Set<SubtitlePunctuationGroup> = [.questionMark, .ellipsis, .quotes]

    let output = SubtitleTextFormatting.applyingPunctuationPolicy(
        input,
        retained: retained
    )

    #expect(output == "他说 “Final Cut Pro……真的好用吗？” 当然")
}

@Test func punctuationPolicyKeepsEnglishEllipsisAsOneToken() {
    let output = SubtitleTextFormatting.applyingPunctuationPolicy(
        "等等...真的？",
        retained: [.ellipsis]
    )

    #expect(output == "等等...真的")
}

@Test func hotwordsAreNormalizedWithoutPersistingVariants() {
    let hotwords = HotwordInputParser.parse(
        " subForge，Final cut pro\nsubForge, GitHub \n"
    )

    #expect(hotwords == ["subForge", "Final cut pro", "GitHub"])
    let prompt = ProofreadingPromptComposer.userPrompt(
        basePrompt: "只修正识别错误。",
        hotwords: hotwords
    )
    #expect(prompt.contains("- subForge"))
    #expect(prompt.contains("- Final cut pro"))
    #expect(prompt.contains("热词严格区分大小写、空格和符号"))
    #expect(prompt.contains("不要把热词自动改成全大写、全小写或首字母大写"))
    #expect(prompt.contains("用户不会提供错误变体"))
}

@Test func enabledFixedHotwordsMergeWithPerVideoHotwords() {
    var settings = AppSettings()
    settings.fixedHotwordsEnabled = true
    settings.fixedHotwordsText = "subForge，Final Cut Pro\nGitHub"

    let options = TranscriptionRunOptions(
        settings: settings,
        hotwords: ["Final Cut Pro", "DaVinci Resolve"]
    )

    #expect(options.hotwords == [
        "subForge",
        "Final Cut Pro",
        "GitHub",
        "DaVinci Resolve"
    ])
}

@Test func disabledFixedHotwordsStayStoredButDoNotEnterTask() {
    var settings = AppSettings()
    settings.fixedHotwordsEnabled = false
    settings.fixedHotwordsText = "subForge，Final Cut Pro"

    let options = TranscriptionRunOptions(
        settings: settings,
        hotwords: ["GitHub"]
    )

    #expect(settings.effectiveFixedHotwordsText == "subForge，Final Cut Pro")
    #expect(options.hotwords == ["GitHub"])
}

@Test func proofreadingResponseRequiresCompleteUniqueNumbering() throws {
    let valid = try ProofreadingResponseParser.parse(
        "1. 第一行\n2、第二行",
        expectedCount: 2
    )
    #expect(valid == ["第一行", "第二行"])

    #expect(throws: ProofreadingError.invalidResponse) {
        try ProofreadingResponseParser.parse("第一行\n第二行", expectedCount: 2)
    }
    #expect(throws: ProofreadingError.invalidResponse) {
        try ProofreadingResponseParser.parse("1. 第一行\n1. 重复", expectedCount: 2)
    }
    #expect(throws: ProofreadingError.invalidResponse) {
        try ProofreadingResponseParser.parse("1. 第一行\n2. ", expectedCount: 2)
    }
}
