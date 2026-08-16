import Foundation

enum FCPXMLExportConfiguration {
    static let titleEffectName = "基本标题"
    static let titleEffectUID = ".../Titles.localized/Bumper:Opener.localized/Basic Title.localized/Basic Title.moti"
    static let titleSourceStart = "0s"
    static let titlePositionParameterKey = "9999/999166631/999166633/1/100/101"
}

struct FCPXMLTimelineItem {
    enum Kind {
        case gap(index: Int)
        case title(index: Int, segment: SubtitleSegment)
    }

    let startFrame: Int
    let endFrame: Int
    let kind: Kind

    var durationFrames: Int { endFrame - startFrame }
}

enum FCPXMLTimelinePlanner {
    static func makeItems(
        segments: [SubtitleSegment],
        totalDuration: TimeInterval,
        fps: Int
    ) -> [FCPXMLTimelineItem] {
        let safeFPS = max(fps, 1)
        let totalEndFrame = totalEndFrame(
            segments: segments,
            requestedDuration: totalDuration,
            fps: safeFPS
        )
        let sortedSegments = segments.sorted { $0.start < $1.start }
        var items: [FCPXMLTimelineItem] = []
        var cursorFrame = 0
        var gapIndex = 1
        var titleIndex = 1

        for segment in sortedSegments {
            let startFrame = max(frameIndex(segment.start, fps: safeFPS), cursorFrame)
            let endFrame = max(frameIndex(segment.end, fps: safeFPS), startFrame + 1)

            if startFrame > cursorFrame {
                items.append(.init(
                    startFrame: cursorFrame,
                    endFrame: startFrame,
                    kind: .gap(index: gapIndex)
                ))
                gapIndex += 1
            }

            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                items.append(.init(
                    startFrame: startFrame,
                    endFrame: endFrame,
                    kind: .gap(index: gapIndex)
                ))
                gapIndex += 1
            } else {
                items.append(.init(
                    startFrame: startFrame,
                    endFrame: endFrame,
                    kind: .title(index: titleIndex, segment: segment)
                ))
                titleIndex += 1
            }
            cursorFrame = endFrame
        }

        if totalEndFrame > cursorFrame {
            items.append(.init(
                startFrame: cursorFrame,
                endFrame: totalEndFrame,
                kind: .gap(index: gapIndex)
            ))
        }

        return items
    }

    static func totalEndFrame(
        segments: [SubtitleSegment],
        requestedDuration: TimeInterval,
        fps: Int
    ) -> Int {
        let safeFPS = max(fps, 1)
        let requiredSubtitleEnd = segments.reduce(1) { latestFrame, segment in
            let startFrame = frameIndex(segment.start, fps: safeFPS)
            let endFrame = max(frameIndex(segment.end, fps: safeFPS), startFrame + 1)
            return max(latestFrame, endFrame)
        }
        return max(frameIndex(requestedDuration, fps: safeFPS), requiredSubtitleEnd)
    }

    static func frameIndex(_ seconds: TimeInterval, fps: Int) -> Int {
        max(Int((max(seconds, 0) * Double(max(fps, 1))).rounded()), 0)
    }
}
