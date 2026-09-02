import Testing
@testable import SubForge

@Test func fcpxmlTimelineUsesContiguousIntegerFrameRanges() throws {
    let segments = [
        SubtitleSegment(start: 0.32, end: 2.80, text: "第一条"),
        SubtitleSegment(start: 2.88, end: 6.08, text: "第二条"),
        SubtitleSegment(start: 10.88, end: 14.56, text: "第三条"),
        SubtitleSegment(start: 14.96, end: 16.40, text: "第四条"),
        SubtitleSegment(start: 20.32, end: 21.28, text: "第五条"),
        SubtitleSegment(start: 21.26, end: 23.92, text: "第六条"),
        SubtitleSegment(start: 60.42, end: 62.90, text: "一分钟后的字幕")
    ]

    let items = FCPXMLTimelinePlanner.makeItems(
        segments: segments,
        totalDuration: 65,
        fps: 30
    )

    #expect(try #require(items.first).startFrame == 0)
    #expect(try #require(items.last).endFrame == 1_950)
    #expect(items.allSatisfy { $0.durationFrames > 0 })

    for (previous, next) in zip(items, items.dropFirst()) {
        #expect(previous.endFrame == next.startFrame)
    }
}

@Test func fcpxmlTimelineTurnsEmptySubtitlesIntoGaps() {
    let items = FCPXMLTimelinePlanner.makeItems(
        segments: [SubtitleSegment(start: 1, end: 2, text: "  \n")],
        totalDuration: 3,
        fps: 30
    )

    #expect(items.count == 3)
    #expect(items.allSatisfy { item in
        if case .title = item.kind { return false }
        return true
    })
}

@Test func fcpxmlTimelineSortsSegmentsBeforePlanning() throws {
    let items = FCPXMLTimelinePlanner.makeItems(
        segments: [
            SubtitleSegment(start: 4, end: 5, text: "第二条"),
            SubtitleSegment(start: 1, end: 2, text: "第一条")
        ],
        totalDuration: 5,
        fps: 30
    )

    let titles = items.compactMap { item -> SubtitleSegment? in
        guard case .title(_, let segment) = item.kind else { return nil }
        return segment
    }
    #expect(titles.map(\.text) == ["第一条", "第二条"])
    #expect(try #require(items.last).endFrame == 150)
}

@Test func fcpxmlTimelineAlwaysCoversTheLatestSubtitle() {
    let segments = [
        SubtitleSegment(start: 8, end: 9, text: "较晚字幕"),
        SubtitleSegment(start: 1, end: 2, text: "较早字幕")
    ]

    let totalEndFrame = FCPXMLTimelinePlanner.totalEndFrame(
        segments: segments,
        requestedDuration: 3,
        fps: 30
    )

    #expect(totalEndFrame == 270)
}

@Test func fcpxmlTimelineUsesConfigured25Fps() throws {
    let items = FCPXMLTimelinePlanner.makeItems(
        segments: [SubtitleSegment(start: 600, end: 601, text: "十分钟后的字幕")],
        totalDuration: 601,
        fps: 25
    )

    let title = try #require(items.first { item in
        if case .title = item.kind { return true }
        return false
    })

    #expect(title.startFrame == 15_000)
    #expect(title.endFrame == 15_025)
}

@Test func fcpxmlUsesStaticBasicTitleTemplate() {
    #expect(FCPXMLExportConfiguration.titleEffectName == "基本标题")
    #expect(FCPXMLExportConfiguration.titleEffectUID.contains("Basic Title"))
    #expect(!FCPXMLExportConfiguration.titleEffectUID.contains("Custom.moti"))
    #expect(FCPXMLExportConfiguration.titleSourceStart == "0s")
}
