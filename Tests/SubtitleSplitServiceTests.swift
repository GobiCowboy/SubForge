import Foundation
import Testing

@testable import SubForge

@Test func splitAtCaretPreservesTextAndMakesContinuousSegments() throws {
  let segment = SubtitleSegment(start: 0, end: 10, text: "这是一个测试句子")
  let result = try SubtitleSplitService.splitAtCaret(segment, utf16Offset: 6)

  #expect(result.left.text == "这是一个测试")
  #expect(result.right.text == "句子")
  #expect(result.left.end == result.right.start)
  #expect(result.left.start == 0)
  #expect(result.right.end == 10)
  #expect(result.usesEstimatedTime)
}

@Test func splitAtCaretUsesWordTimestampAtWordBoundary() throws {
  let segment = SubtitleSegment(
    start: 0,
    end: 8,
    text: "这是第一句话。第二句。",
    words: [
      SubtitleWord(start: 0, end: 1.5, text: "这是"),
      SubtitleWord(start: 1.5, end: 3, text: "第一句话。"),
      SubtitleWord(start: 3.5, end: 5, text: "第二句。"),
    ]
  )

  let result = try SubtitleSplitService.splitAtCaret(segment, utf16Offset: 7)

  #expect(result.left.text == "这是第一句话。")
  #expect(result.right.text == "第二句。")
  #expect(result.splitTime == 3)
  #expect(!result.usesEstimatedTime)
  #expect(result.left.words?.map(\.text) == ["这是", "第一句话。"])
  #expect(result.right.words?.map(\.text) == ["第二句。"])
}

@Test func playbackCaretFollowsTimedWordsAndInterpolatesInsideWords() {
  let segment = SubtitleSegment(
    start: 0,
    end: 6,
    text: "这是一个测试",
    words: [
      SubtitleWord(start: 0, end: 1, text: "这"),
      SubtitleWord(start: 1, end: 2, text: "是"),
      SubtitleWord(start: 2, end: 4, text: "一个"),
      SubtitleWord(start: 4, end: 6, text: "测试"),
    ]
  )

  #expect(SubtitleSplitService.caretOffset(at: 0.5, in: segment) == 0)
  #expect(SubtitleSplitService.caretOffset(at: 1.0, in: segment) == 1)
  #expect(SubtitleSplitService.caretOffset(at: 3.0, in: segment) == 3)
  #expect(SubtitleSplitService.caretOffset(at: 5.0, in: segment) == 5)
}

@Test func playbackCaretFallsBackToCharacterProportionWithoutWordTimestamps() {
  let segment = SubtitleSegment(start: 0, end: 4, text: "你好世界")

  #expect(SubtitleSplitService.caretOffset(at: 2, in: segment) == 2)
}

@Test func splitInsideTimedWordInterpolatesAndKeepsWordMetadata() throws {
  let segment = SubtitleSegment(
    start: 0,
    end: 4,
    text: "FinalCut",
    words: [SubtitleWord(start: 0, end: 4, text: "FinalCut")]
  )

  let result = try SubtitleSplitService.splitAtCaret(segment, utf16Offset: 5)

  #expect(result.left.text == "Final")
  #expect(result.right.text == "Cut")
  #expect(result.left.words?.first?.end == 2.5)
  #expect(result.right.words?.first?.start == 2.5)
}

@Test func splitAtPlayheadSnapsToNearestWordBoundary() throws {
  let segment = SubtitleSegment(
    start: 0,
    end: 8,
    text: "第一句第二句",
    words: [
      SubtitleWord(start: 0, end: 2.2, text: "第一句"),
      SubtitleWord(start: 2.2, end: 5.5, text: "第二句"),
    ]
  )

  let result = try SubtitleSplitService.splitAtPlayhead(segment, time: 2.4)

  #expect(result.left.text == "第一句")
  #expect(result.right.text == "第二句")
  #expect(result.splitTime == 2.4)
  #expect(!result.usesEstimatedTime)
}

@Test func splitRejectsCaretAtTextEdge() {
  let segment = SubtitleSegment(start: 0, end: 2, text: "字幕")

  #expect(throws: SubtitleSplitError.emptySide) {
    try SubtitleSplitService.splitAtCaret(segment, utf16Offset: 0)
  }
  #expect(throws: SubtitleSplitError.emptySide) {
    try SubtitleSplitService.splitAtCaret(segment, utf16Offset: segment.text.utf16.count)
  }
}
