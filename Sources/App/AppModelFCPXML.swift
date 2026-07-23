import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

extension AppModel {
    func makeFCPXML(projectName: String, segments: [SubtitleSegment]) -> String {
        let style = settings.subtitleStyle
        let fps = max(settings.exportSettings.fps, 1)
        let format = fcpxmlFormat(for: style.canvasOrientation, fps: fps)
        let totalSeconds = max(playbackDuration, segments.last?.end ?? 1)
        let totalDuration = fcpxmlTime(totalSeconds, fps: fps, minimumFrames: 1)
        let storylineItems = makeFCPXMLStorylineItems(
            segments: segments,
            totalDuration: totalSeconds,
            style: style,
            fps: fps
        )

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE fcpxml>
        <fcpxml version="1.14">
          <resources>
            <format id="r1" name="\(format.name)" frameDuration="1/\(fps)s" width="\(format.width)" height="\(format.height)" colorSpace="1-1-1 (Rec. 709)"/>
            <effect id="r2" name="自定" uid=".../Titles.localized/Build In:Out.localized/Custom.localized/Custom.moti"/>
          </resources>
          <library>
            <event name="SubForge Export">
              <project name="\(escapeXML(projectName))">
                <sequence format="r1" tcStart="0s" tcFormat="NDF" duration="\(totalDuration)" audioLayout="stereo" audioRate="48k">
                  <spine>
                    <gap name="空隙" offset="0s" start="3600s" duration="\(totalDuration)">
                      <spine lane="1" offset="3600s">
        \(storylineItems)
                      </spine>
                    </gap>
                  </spine>
                </sequence>
              </project>
            </event>
          </library>
        </fcpxml>
        """
    }

    func makeFCPXMLStorylineItems(
        segments: [SubtitleSegment],
        totalDuration: Double,
        style: SubtitleStyle,
        fps: Int
    ) -> String {
        let sortedSegments = segments.sorted { $0.start < $1.start }
        var items: [String] = []
        var cursor: Double = 0
        var blankIndex = 1
        var titleIndex = 1
        let frameDuration = 1 / Double(fps)

        for segment in sortedSegments {
            let start = max(segment.start, cursor)
            if start - cursor >= frameDuration / 2 {
                items.append(makeFCPXMLGap(
                    index: blankIndex,
                    offset: cursor,
                    duration: start - cursor,
                    fps: fps
                ))
                blankIndex += 1
                cursor = start
            }

            let end = max(segment.end, start)
            let duration = max(end - start, frameDuration)
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)

            if text.isEmpty {
                items.append(makeFCPXMLGap(
                    index: blankIndex,
                    offset: start,
                    duration: duration,
                    fps: fps
                ))
                blankIndex += 1
                cursor = max(cursor, end)
                continue
            }

            items.append(makeFCPXMLTitle(
                segment: segment,
                index: titleIndex,
                offset: start,
                duration: duration,
                style: style,
                fps: fps
            ))
            titleIndex += 1
            cursor = max(cursor, end)
        }

        if totalDuration - cursor >= frameDuration / 2 {
            items.append(makeFCPXMLGap(
                index: blankIndex,
                offset: cursor,
                duration: totalDuration - cursor,
                fps: fps
            ))
        }

        return items.joined(separator: "\n")
    }

    func makeFCPXMLGap(index: Int, offset: Double, duration: Double, fps: Int) -> String {
        let safeDuration = max(duration, 0)
        let name = "Blank \(formatFCPXMLTimestamp(offset))-\(formatFCPXMLTimestamp(offset + safeDuration))"
        return """
                        <gap name="\(escapeXML(name))" offset="\(fcpxmlTime(offset, fps: fps))" duration="\(fcpxmlTime(safeDuration, fps: fps))"/>
        """
    }

    func makeFCPXMLTitle(
        segment: SubtitleSegment,
        index: Int,
        offset: Double,
        duration: Double,
        style: SubtitleStyle,
        fps: Int
    ) -> String {
        let textStyleID = "ts\(index)"
        let name = escapeXML(firstFCPXMLTitleLine(segment.text, fallback: "Caption \(index)"))
        let position = fcpxmlTitlePosition(style)
        let styleAttributes = fcpxmlTextStyleAttributes(style)

        return """
                        <title ref="r2" offset="\(fcpxmlTime(offset, fps: fps))" name="\(name)" duration="\(fcpxmlTime(duration, fps: fps, minimumFrames: 1))">
                          <param name="位置" key="9999/10199/10201/1/100/101" value="\(position.x) \(position.y) \(position.z)"/>
                          <param name="对齐" key="9999/10199/10201/2/354/1002961760/401" value="1 (居中)"/>
                          <param name="对齐" key="9999/10199/10201/2/373" value="0 (左) 2 (下)"/>
                          <param name="Out Sequencing" key="9999/10199/10201/4/10233/201/202" value="0 (到)"/>
                          <param name="disableDRT" key="3733" value="1"/>
                          <text>
                            <text-style ref="\(textStyleID)">\(escapeXML(segment.text))</text-style>
                          </text>
                          <text-style-def id="\(textStyleID)">
                            <text-style \(styleAttributes)/>
                          </text-style-def>
                          <adjust-colorConform enabled="1" autoOrManual="manual" conformType="conformNone" peakNitsOfPQSource="1000" peakNitsOfSDRToPQSource="203"/>
                        </title>
        """
    }

    struct FCPXMLFormat {
        let name: String
        let width: Int
        let height: Int
    }

    func fcpxmlFormat(for orientation: SubtitleCanvasOrientation, fps: Int) -> FCPXMLFormat {
        switch orientation {
        case .landscape:
            FCPXMLFormat(name: "FFVideoFormat1920x1080p\(fps * 100)", width: 1920, height: 1080)
        case .portrait:
            FCPXMLFormat(name: "FFVideoFormat1080x1920p\(fps * 100)", width: 1080, height: 1920)
        }
    }

    func fcpxmlTime(_ seconds: Double, fps: Int, minimumFrames: Int = 0) -> String {
        let frames = max(Int(round(seconds * Double(fps))), minimumFrames)
        if frames == 0 {
            return "0s"
        }
        return "\(frames)/\(fps)s"
    }

    func formatFCPXMLTimestamp(_ seconds: Double) -> String {
        let clampedSeconds = max(seconds, 0)
        let minutes = Int(clampedSeconds / 60)
        let remainingSeconds = clampedSeconds - Double(minutes * 60)
        return String(format: "%02d:%06.3f", minutes, remainingSeconds)
    }

    func firstFCPXMLTitleLine(_ text: String, fallback: String) -> String {
        let line = text.components(separatedBy: .newlines).first ?? text
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        return trimmed.count <= 64 ? trimmed : String(trimmed.prefix(64))
    }

    func fcpxmlTitlePosition(_ style: SubtitleStyle) -> (x: String, y: String, z: String) {
        (
            formatFCPXMLNumber(style.positionX),
            formatFCPXMLNumber(style.positionY),
            formatFCPXMLNumber(style.positionZ)
        )
    }

    func fcpxmlTextStyleAttributes(_ style: SubtitleStyle) -> String {
        let fontFace: String
        switch style.fontWeight {
        case .regular:
            fontFace = "Regular"
        case .medium:
            fontFace = "Medium"
        case .semibold:
            fontFace = "Semibold"
        case .bold:
            fontFace = "Bold"
        }

        let alignment: String
        switch style.horizontalAlignment {
        case .leading:
            alignment = "left"
        case .center:
            alignment = "center"
        case .trailing:
            alignment = "right"
        }

        let strokeColor: String
        let strokeWidth: String
        if style.outlineEnabled {
            strokeColor = fcpxmlColor(style.outlineColorHex, alpha: style.outlineOpacity)
            strokeWidth = formatFCPXMLNumber(-max(style.outlineWidth, 0.5))
        } else if style.surfaceEnabled {
            strokeColor = fcpxmlColor(style.surfaceColorHex, alpha: style.surfaceOpacity)
            strokeWidth = formatFCPXMLNumber(-max(8, style.fontSize * 0.18))
        } else {
            strokeColor = fcpxmlColor("#000000", alpha: 0)
            strokeWidth = "0"
        }

        return """
        font="\(escapeXML(style.fontFamily))" fontSize="\(formatFCPXMLNumber(style.fontSize))" fontFace="\(fontFace)" fontColor="\(fcpxmlColor(style.fontColorHex))" strokeColor="\(strokeColor)" strokeWidth="\(strokeWidth)" alignment="\(alignment)"
        """
    }

    func fcpxmlColor(_ hex: String, alpha: Double = 1) -> String {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = Int(trimmed, radix: 16) ?? 0
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255

        return [
            formatFCPXMLNumber(red),
            formatFCPXMLNumber(green),
            formatFCPXMLNumber(blue),
            formatFCPXMLNumber(max(0, min(alpha, 1)))
        ].joined(separator: " ")
    }

    func formatFCPXMLNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }

        return String(format: "%.4f", value)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }
}
