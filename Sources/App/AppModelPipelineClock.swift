import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

extension AppModel {
    func handleFunASRHeartbeat(_ notification: Notification) {
        guard mode == .progress else { return }
        // 秒表仍用流水线总时长；此处只用音频时长缓动进度条
        if let duration = notification.userInfo?["duration"] as? TimeInterval, duration > 0 {
            pipelineAudioDuration = duration
        }
        let wall = pipelineElapsedSeconds()
        if pipelineAudioDuration > 0 {
            let ratio = min(0.92, Double(wall) / max(pipelineAudioDuration * 0.9 + 15, 1))
            pipelineProgress = 0.36 + ratio * 0.34
        } else {
            pipelineProgress = min(0.68, 0.36 + Double(wall) * 0.004)
        }
        refreshPipelineStatusMessage()
    }

    func startPipelineClock(modelLabel: String, usesLocalEngine: Bool) {
        pipelineStartedAt = Date()
        pipelineModelLabel = modelLabel
        pipelineUsesLocalEngine = usesLocalEngine
        pipelinePhaseLabel = "准备中"
        pipelineAudioDuration = 0
        pipelineTickerTask?.cancel()
        pipelineTickerTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, self.mode == .progress {
                self.refreshPipelineStatusMessage()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        refreshPipelineStatusMessage()
    }

    func stopPipelineClock() {
        pipelineTickerTask?.cancel()
        pipelineTickerTask = nil
        pipelineStartedAt = nil
        pipelineAudioDuration = 0
    }

    func updatePipelineClockContext(modelLabel: String, usesLocalEngine: Bool) {
        pipelineModelLabel = modelLabel
        pipelineUsesLocalEngine = usesLocalEngine
        refreshPipelineStatusMessage()
    }

    func pipelineElapsedSeconds() -> Int {
        guard let start = pipelineStartedAt else { return 0 }
        return max(0, Int(Date().timeIntervalSince(start).rounded(.down)))
    }

    func setPipelinePhase(_ phase: String, progress: Double? = nil) {
        pipelinePhaseLabel = phase
        if let progress {
            pipelineProgress = progress
        }
        refreshPipelineStatusMessage()
    }

    /// 例：`FunASR · 转写中 · 12s`（时间固定放最后）
    func refreshPipelineStatusMessage() {
        guard mode == .progress else { return }
        let elapsed = pipelineElapsedSeconds()
        var parts: [String] = []
        if !pipelineModelLabel.isEmpty {
            parts.append(pipelineModelLabel)
        }
        if !pipelinePhaseLabel.isEmpty {
            parts.append(pipelinePhaseLabel)
        }
        parts.append("\(elapsed)s")
        pipelineMessage = parts.joined(separator: " · ")
    }

    /// 进度条文案用短名称：FunASR / Whisper / Apple 语音 / 云端 ASR
    func displayName(for engine: TranscriptionEngine, settings: AppSettings) -> String {
        switch engine {
        case .funASRLocal:
            return "FunASR"
        case .whisperLocal:
            return "Whisper"
        case .appleSpeech:
            return "Apple 语音"
        case .officialSmart:
            return "智能字幕"
        case .cloudASR:
            return "云端 ASR"
        }
    }
}
