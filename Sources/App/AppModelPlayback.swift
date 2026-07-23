import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

extension AppModel {
    func togglePlayback() {
        guard mode == .editor else { return }
        if isEditingSubtitle {
            endEditingSubtitle()
        }
        isPlaying ? stopPlayback() : startPlayback()
    }

    func skip(by seconds: TimeInterval) {
        guard mode == .editor else { return }
        seek(to: currentTime + seconds)
    }

    func seek(to time: TimeInterval) {
        currentTime = max(0, min(time, playbackDuration))
        if playbackService.hasLoadedMedia {
            playbackService.seek(to: currentTime)
        }
        syncSelectionToCurrentTime()
    }

    func setPlaybackRate(_ rate: Double) {
        playbackRate = rate
        playbackService.setRate(rate)
    }

    func handleBackwardPlaybackShortcut() {
        AppLog.editor.info(
            "shortcut J currentTime=\(self.currentTime, privacy: .public) playing=\(self.isPlaying, privacy: .public) editing=\(self.isEditingSubtitle, privacy: .public)"
        )
        if isEditingSubtitle {
            endEditingSubtitle()
        }
        stopPlayback(captureTimestamp: false)
        seek(to: currentTime - 1)
        showToast("已后退 1 秒", level: .info)
    }

    func handlePausePlaybackShortcut() {
        AppLog.editor.info(
            "shortcut K currentTime=\(self.currentTime, privacy: .public) playing=\(self.isPlaying, privacy: .public) editing=\(self.isEditingSubtitle, privacy: .public)"
        )
        if isPlaying {
            stopPlayback()
        } else {
            captureCurrentTimestamp()
        }
    }

    func handleForwardPlaybackShortcut() {
        AppLog.editor.info(
            "shortcut L currentTime=\(self.currentTime, privacy: .public) playing=\(self.isPlaying, privacy: .public) editing=\(self.isEditingSubtitle, privacy: .public) rate=\(self.playbackRate, privacy: .public)"
        )
        if isEditingSubtitle {
            endEditingSubtitle()
        }

        let rates: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
        let currentIndex = rates.firstIndex(where: { abs($0 - playbackRate) < 0.001 }) ?? 2
        let targetRate = isPlaying
            ? rates[(currentIndex + 1) % rates.count]
            : rates[currentIndex]

        playbackRate = targetRate
        startPlayback()
        showToast("正向播放 \(String(format: "%.2g", targetRate))x", level: .info)
    }

    func handleSpacePlaybackShortcut() {
        guard mode == .editor else { return }

        AppLog.editor.info(
            "spaceShortcut playing=\(self.isPlaying, privacy: .public) editing=\(self.isEditingSubtitle, privacy: .public) selected=\(String(describing: self.selectedSegmentID), privacy: .public) currentTime=\(self.currentTime, privacy: .public)"
        )

        if isEditingSubtitle {
            endEditingSubtitle()
            startPlayback()
            return
        }

        if isPlaying {
            stopPlayback()
            if selectedSegmentID == nil {
                selectedSegmentID = segments.first?.id
            }
            beginEditingSelectedSubtitle()
            return
        }

        if selectedSegmentID == nil {
            selectedSegmentID = segments.first?.id
        }

        if playbackDuration > 0 {
            startPlayback()
        } else {
            beginEditingSelectedSubtitle()
        }
    }

    func startPlayback() {
        guard playbackDuration > 0 else { return }
        stopPlayback(captureTimestamp: false)

        if currentTime >= max(playbackDuration - 0.05, 0), playbackDuration > 0.05 {
            currentTime = 0
            if playbackService.hasLoadedMedia {
                playbackService.seek(to: 0)
            }
        }

        // 音频项目：必须走 AVPlayer。SRT 无音频时才用合成时钟推进时间轴。
        let isAudioDocument = currentDocumentURL.map { mediaKind(for: $0) == "audio" } ?? false
        if isAudioDocument {
            if !playbackService.hasLoadedMedia || !playbackService.canPlay {
                // 再试一次：用沙箱副本重载（导入时偶发 AVPlayerItem 未就绪/失败）。
                if let url = currentDocumentURL {
                    prepareMediaPreview(for: url)
                }
            }

            guard playbackService.hasLoadedMedia, playbackService.canPlay else {
                showToast("无法播放音频：文件可能不可读或格式不受支持", level: .error, duration: 4)
                return
            }

            isPlaying = true
            playbackService.seek(to: currentTime)
            playbackService.play(rate: playbackRate)
            return
        }

        isPlaying = true

        if playbackService.hasLoadedMedia, playbackService.canPlay {
            playbackService.seek(to: currentTime)
            playbackService.play(rate: playbackRate)
            return
        }

        // 仅 SRT：无真实音频，用计时器驱动时间轴高亮。
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.currentTime += 0.05 * self.playbackRate
                if self.currentTime >= self.playbackDuration {
                    self.currentTime = self.playbackDuration
                    self.stopPlayback()
                }
                self.syncSelectionToCurrentTime()
            }
        }
    }

    func stopPlayback(captureTimestamp: Bool = true) {
        let wasPlaying = isPlaying
        playbackTimer?.invalidate()
        playbackTimer = nil
        playbackService.pause()
        isPlaying = false

        if wasPlaying, captureTimestamp {
            captureCurrentTimestamp()
        }
    }

    func finishPlayback() {
        currentTime = playbackDuration
        playbackTimer?.invalidate()
        playbackTimer = nil
        isPlaying = false
        syncSelectionToCurrentTime()
    }

    func handlePlaybackTimeUpdate(_ time: TimeInterval) {
        guard isPlaying else { return }
        currentTime = max(0, min(time, playbackDuration))
        syncSelectionToCurrentTime()
    }

    func prepareMediaPreview(for url: URL) {
        // 与转写同一策略：外部文件先拷进沙箱 temp，再交给 AVPlayer / 波形分析。
        // 直接播用户原路径时，App Sandbox 下 AVPlayer 经常创建成功但静默无声。
        cleanupPlaybackLocalMedia()

        let previewURL: URL
        do {
            let prepared = try SandboxMediaAccess.prepareForProcessing(url)
            if prepared.isTemporaryCopy {
                playbackLocalMedia = prepared
                previewURL = prepared.url
                AppLog.import.info(
                    "playback media sandbox copy ready source=\(url.lastPathComponent, privacy: .public)"
                )
            } else {
                previewURL = prepared.url
                AppLog.import.info(
                    "playback media direct path source=\(url.lastPathComponent, privacy: .public)"
                )
            }
        } catch {
            previewURL = url
            AppLog.import.warning(
                "playback media prepare failed, fallback original error=\(error.localizedDescription, privacy: .public)"
            )
        }

        playbackService.loadMedia(from: previewURL)
        waveformTask?.cancel()
        waveformSamples = []
        let analyzeURL = previewURL
        waveformTask = Task { [weak self] in
            let samples = await WaveformAnalysisService.analyze(url: analyzeURL)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.waveformSamples = samples
            }
        }
    }

    func cleanupPlaybackLocalMedia() {
        playbackLocalMedia?.cleanup()
        playbackLocalMedia = nil
    }

    func clearPlaybackMedia() {
        waveformTask?.cancel()
        waveformTask = nil
        cleanupPlaybackLocalMedia()
        playbackService.clear()
    }
}
