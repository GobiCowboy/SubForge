import Foundation

/// FCPXML 1.9 生成器（与 Python fcpxml.py 对齐）
enum FCPXMLGenerator {
    /// 根据字幕分段生成 FCPXML
    static func generate(
        segments: [SubtitleSegment],
        projectName: String,
        fps: Int = 30,
        width: Int = 1920,
        height: Int = 1080,
        style: SubtitleStyle = SubtitleStyle()
    ) -> String {
        let (frameNum, frameDen) = frameDuration(fps)
        let formatName = "FFVideoFormat\(width)x\(height)p\(fps * 100)"
        let projectStart = Int(round(3.6 * Double(frameDen)))
        let projectStartStr = "\(projectStart)/\(frameDen)s"

        // 总时长
        let totalDur = segments.last.map { $0.end } ?? 10.0
        let totalDurStr = toRational(totalDur, frameNum, frameDen)

        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE fcpxml>
        <fcpxml version="1.9">
            <resources>
                <format id="r1" name="\(formatName)" frameDuration="\(frameNum)/\(frameDen)s" width="\(width)" height="\(height)" colorSpace="1-1-1 (Rec. 709)"/>
                <effect id="r2" name="Custom" uid=".../Titles.localized/Build In:Out.localized/Custom.localized/Custom.moti"/>
            </resources>
            <library>
                <event name="\(esc(projectName))">
                    <project name="\(esc(projectName))">
                        <sequence format="r1" tcStart="0s" tcFormat="NDF" duration="\(totalDurStr)" audioLayout="stereo" audioRate="48k">
                            <spine>
                                <gap name="字幕" offset="0s" start="\(projectStartStr)" duration="\(totalDurStr)">
                                    <spine lane="1" offset="\(firstConnectedOffset(segments, frameNum, frameDen, projectStart))">

        """

        // 第一条字幕的起始时间（用于计算相对偏移）
        let firstOffset = segments.first.map { $0.start } ?? 0

        for (idx, seg) in segments.enumerated() {
            let duration = seg.end - seg.start
            guard duration > 0 else { continue }

            let num = idx + 1
            let tsId = "ts\(num)"
            let relOffset = seg.start - firstOffset
            let offsetStr = toRational(relOffset, frameNum, frameDen)
            let durationStr = toRational(duration, frameNum, frameDen)
            let name = firstLine(seg.text)

            xml += """
                                        <title ref="r2" offset="\(offsetStr)" name="\(esc(name))" duration="\(durationStr)" start="\(projectStartStr)">
                                            <param name="Position" key="9999/10199/10201/1/100/101" value="0 -495"/>
                                            <param name="Alignment" key="9999/10199/10201/2/354/1002961760/401" value="1 (Center)"/>
                                            <param name="Alignment" key="9999/10199/10201/2/373" value="0 (Left) 2 (Bottom)"/>
                                            <param name="Color" key="9999/10199/10201/5/10203/30/32" value="0 0 0"/>
                                            <param name="Wrap Mode" key="9999/10199/10201/5/10203/30/34/5" value="1 (Repeat)"/>
                                            <param name="Width" key="9999/10199/10201/5/10203/30/36" value="3"/>
                                            <text>
                                                <text-style ref="\(tsId)">\(esc(seg.text))</text-style>
                                            </text>
                                            <text-style-def id="\(tsId)">
                                                <text-style font="PingFang SC" fontSize="48" fontFace="Regular" fontColor="0.999996 1 1 1" strokeColor="0 0 0 1" strokeWidth="-3" alignment="center"/>
                                            </text-style-def>
                                        </title>

            """
        }

        xml += """
                                    </spine>
                                </gap>
                            </spine>
                        </sequence>
                    </project>
                </event>
            </library>
        </fcpxml>
        """

        return xml
    }

    // MARK: - 辅助函数

    /// 计算帧时长 (分子, 分母)
    private static func frameDuration(_ fps: Int) -> (Int, Int) {
        return (1, fps)
    }

    /// 秒数转 FCPXML 有理数时间，对齐到帧边界
    private static func toRational(_ seconds: Double, _ frameNum: Int, _ frameDen: Int) -> String {
        let ticks = Int(round(seconds * Double(frameDen) / Double(frameNum)))
        return "\(ticks * frameNum)/\(frameDen)s"
    }

    /// 第一条字幕的连接故事情节偏移
    private static func firstConnectedOffset(_ segments: [SubtitleSegment], _ frameNum: Int, _ frameDen: Int, _ projectStart: Int) -> String {
        let firstStart = segments.first.map { $0.start } ?? 0
        let offset = firstStart + Double(projectStart) / Double(frameDen)
        return toRational(offset, frameNum, frameDen)
    }

    /// 取文本第一行，最长 64 字符
    private static func firstLine(_ text: String) -> String {
        let line = text.components(separatedBy: .newlines).first ?? text
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.count <= 64 { return trimmed }
        return String(trimmed.prefix(64))
    }

    /// XML 转义
    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
