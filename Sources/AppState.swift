import Foundation
import Combine
import AppKit

/// 全局应用状态
@MainActor
final class AppState: ObservableObject {
    // MARK: - 字幕数据
    @Published var segments: [SubtitleSegment] = []
    @Published var activeIndex: Int = -1
    @Published var isModified: Bool = false
    @Published var audioFileURL: URL?

    // MARK: - 播放状态
    @Published var isPlaying: Bool = false

    // MARK: - 设置
    @Published var settings = SettingsManager.load()
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackRate: Float = 1.0

    // MARK: - 编辑状态（全局唯一）
    @Published var editingIndex: Int? = nil

    // MARK: - 转写状态
    @Published var isTranscribing: Bool = false
    @Published var transcriptionProgress: String = ""
    @Published var transcriptionStep: PipelineStepStatus = .pending
    @Published var proofreadingStep: PipelineStepStatus = .pending
    @Published var pipelineProgress: Double = 0


    // MARK: - Toast
    @Published var toastMessage: String?
    @Published var toastType: ToastType = .info

    // MARK: - 保存状态快照（用于 dirty 检测）
    private var savedSegmentsSnapshot: String = ""

    var canSave: Bool {
        !segments.isEmpty
    }

    var isDirty: Bool {
        let current = segments.map { "\($0.start)-\($0.end)-\($0.text)" }.joined(separator: "|")
        return current != savedSegmentsSnapshot
    }

    // MARK: - 文件操作

    func loadAudioFile(url: URL) {
        audioFileURL = url
        segments = []
        activeIndex = -1
        isModified = false
        savedSegmentsSnapshot = ""
    }

    /// 返回首页，重置所有状态
    func reset() {
        audioFileURL = nil
        segments = []
        activeIndex = -1
        isModified = false
        savedSegmentsSnapshot = ""
        isTranscribing = false
        transcriptionProgress = ""
        editingIndex = nil
        currentTime = 0
        duration = 0
        isPlaying = false
        transcriptionStep = .pending
        proofreadingStep = .pending
        pipelineProgress = 0
    }

    func setSegments(_ newSegments: [SubtitleSegment]) {
        var result = newSegments

        // 拆分过长的字幕
        let maxLen = settings.maxSubtitleLength
        if maxLen > 0 {
            result = splitLongSegments(result, maxLength: maxLen)
        }

        // 如果第一条字幕不是从 0 开始，补一条空白字幕对齐音轨
        if let first = result.first, first.start > 0.1 {
            let blank = SubtitleSegment(start: 0, end: first.start, text: "")
            result.insert(blank, at: 0)
        }
        segments = result
        savedSegmentsSnapshot = segments.map { "\($0.start)-\($0.end)-\($0.text)" }.joined(separator: "|")
        isModified = false

        // 记录最近文件
        if let url = audioFileURL {
            let ext = url.pathExtension.lowercased()
            let type = ext == "srt" ? "srt" : "audio"
            RecentFileManager.add(url: url, type: type, subtitleCount: segments.count)
        }
    }

    func saveSRT() {
        guard let audioURL = audioFileURL, !segments.isEmpty else { return }
        let outputURL = settings.resolveOutputURL(for: audioURL, extension: "srt")
        let srtContent = SRTParser.generate(segments)
        do {
            try srtContent.write(to: outputURL, atomically: true, encoding: .utf8)
            savedSegmentsSnapshot = segments.map { "\($0.start)-\($0.end)-\($0.text)" }.joined(separator: "|")
            isModified = false
            showToast("已保存 \(outputURL.lastPathComponent)", type: .success)
        } catch {
            showToast("保存失败：\(error.localizedDescription)", type: .error)
        }
    }

    // MARK: - Toast

    func showToast(_ message: String, type: ToastType = .info) {
        toastMessage = message
        toastType = type
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            if self?.toastMessage == message {
                self?.toastMessage = nil
            }
        }
    }

    // MARK: - 播放速率

    func adjustPlaybackRate(faster: Bool) {
        let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
        guard let idx = speeds.firstIndex(of: playbackRate) else {
            playbackRate = 1.0
            return
        }
        let newIdx = faster ? min(idx + 1, speeds.count - 1) : max(idx - 1, 0)
        playbackRate = speeds[newIdx]
        showToast("倍速 \(playbackRate)x", type: .info)
    }

    // MARK: - 复制时间戳

    func copyCurrentTimestamp() {
        let ts = formatTime(currentTime)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ts, forType: .string)
        showToast("已复制 \(ts)", type: .info)
    }
}

// MARK: - Toast 类型

enum ToastType {
    case success, error, info
}

// MARK: - 流水线步骤状态

enum PipelineStepStatus {
    case pending, running, done
}

// MARK: - 时间格式化

func formatTime(_ seconds: TimeInterval) -> String {
    let h = Int(seconds) / 3600
    let m = (Int(seconds) % 3600) / 60
    let s = Int(seconds) % 60
    let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
    return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
}

func parseTime(_ string: String) -> TimeInterval? {
    let cleaned = string.trimmingCharacters(in: .whitespaces)
    // 格式: HH:MM:SS,mmm 或 HH:MM:SS.mmm
    let parts = cleaned.components(separatedBy: CharacterSet(charactersIn: ",."))
    guard parts.count == 2 else { return nil }
    let timeParts = parts[0].components(separatedBy: ":")
    guard timeParts.count == 3,
          let h = Double(timeParts[0]),
          let m = Double(timeParts[1]),
          let s = Double(timeParts[2]) else { return nil }
    let msStr = String(parts[1].prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
    let ms = Double(msStr) ?? 0
    let total = h * 3600.0 + m * 60.0 + s + ms / 1000.0
    return total
}

// MARK: - 字幕拆分

/// 按标点和字数拆分过长的字幕，按比例分配时间
func splitLongSegments(_ segments: [SubtitleSegment], maxLength: Int) -> [SubtitleSegment] {
    var result: [SubtitleSegment] = []

    for seg in segments {
        if seg.text.count <= maxLength || seg.text.isEmpty {
            result.append(seg)
            continue
        }

        // 按标点拆分
        let splitters: [Character] = ["，", "。", "、", "；", "：", "！", "？", ",", ".", ";", ":", "!", "?"]
        var parts: [String] = []
        var current = ""

        for char in seg.text {
            current.append(char)
            if splitters.contains(char) && current.count >= 4 {
                parts.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            parts.append(current)
        }

        // 合并过短的片段
        var merged: [String] = []
        var buffer = ""
        for part in parts {
            if buffer.count + part.count <= maxLength {
                buffer += part
            } else {
                if !buffer.isEmpty { merged.append(buffer) }
                buffer = part
            }
        }
        if !buffer.isEmpty { merged.append(buffer) }

        // 如果合并后仍然有一条超过 maxLength，按字数硬切
        var finalParts: [String] = []
        for part in merged {
            if part.count <= maxLength {
                finalParts.append(part)
            } else {
                var remaining = part
                while remaining.count > maxLength {
                    let splitIdx = remaining.index(remaining.startIndex, offsetBy: maxLength)
                    finalParts.append(String(remaining[remaining.startIndex..<splitIdx]))
                    remaining = String(remaining[splitIdx...])
                }
                if !remaining.isEmpty { finalParts.append(remaining) }
            }
        }

        guard finalParts.count > 1 else {
            result.append(seg)
            continue
        }

        // 按比例分配时间
        let totalChars = finalParts.reduce(0) { $0 + $1.count }
        let totalDuration = seg.end - seg.start
        var currentTime = seg.start

        for part in finalParts {
            let ratio = Double(part.count) / Double(totalChars)
            let duration = totalDuration * ratio
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                result.append(SubtitleSegment(start: currentTime, end: currentTime + duration, text: trimmed))
            }
            currentTime += duration
        }
    }

    return result
}
