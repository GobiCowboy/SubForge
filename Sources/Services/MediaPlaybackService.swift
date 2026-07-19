import AVFoundation
import Foundation

final class MediaPlaybackService {
    var onTimeUpdate: ((TimeInterval) -> Void)?
    var onPlaybackFinished: (() -> Void)?
    var onDurationLoaded: ((TimeInterval) -> Void)?
    var onLoadFailed: ((String) -> Void)?

    private(set) var mediaDuration: TimeInterval = 0
    private(set) var isReadyToPlay = false

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var loadedURL: URL?

    var hasLoadedMedia: Bool {
        player != nil
    }

    /// 播放器已创建，且 item 未失败（ready / unknown 都允许尝试 play）。
    var canPlay: Bool {
        guard let item = player?.currentItem else { return false }
        return item.status != .failed
    }

    func loadMedia(from url: URL?) {
        // 用 path 比较：同一文件不同 URL 实例（security-scoped vs standardized）不应重复装载失败。
        if let url, let loadedURL, loadedURL.path == url.path, player != nil {
            return
        }

        cleanupPlayer()
        loadedURL = url
        mediaDuration = 0
        isReadyToPlay = false

        guard let url else { return }

        let exists = FileManager.default.fileExists(atPath: url.path)
        let readable = FileManager.default.isReadableFile(atPath: url.path)
        AppLog.editor.info(
            "loadMedia path=\(url.lastPathComponent, privacy: .public) exists=\(exists, privacy: .public) readable=\(readable, privacy: .public)"
        )

        guard exists else {
            onLoadFailed?("音频文件不存在")
            return
        }

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.volume = 1
        self.player = player

        statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard let self else { return }
            switch item.status {
            case .readyToPlay:
                self.isReadyToPlay = true
                AppLog.editor.info("AVPlayerItem ready path=\(url.lastPathComponent, privacy: .public)")
            case .failed:
                self.isReadyToPlay = false
                let message = item.error?.localizedDescription ?? "无法解码音频"
                AppLog.editor.error(
                    "AVPlayerItem failed path=\(url.lastPathComponent, privacy: .public) error=\(message, privacy: .public)"
                )
                DispatchQueue.main.async {
                    self.onLoadFailed?(message)
                }
            case .unknown:
                break
            @unknown default:
                break
            }
        }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            let seconds = CMTimeGetSeconds(time)
            guard seconds.isFinite else { return }
            self.onTimeUpdate?(seconds)
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.onPlaybackFinished?()
        }

        Task { [weak self] in
            guard let self else { return }
            let asset = AVURLAsset(url: url)
            do {
                let duration = try await asset.load(.duration)
                let seconds = CMTimeGetSeconds(duration)
                let safeSeconds = seconds.isFinite && !seconds.isNaN ? max(0, seconds) : 0
                await MainActor.run {
                    self.mediaDuration = safeSeconds
                    self.onDurationLoaded?(safeSeconds)
                }
            } catch {
                AppLog.editor.error(
                    "load duration failed path=\(url.lastPathComponent, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                await MainActor.run {
                    self.mediaDuration = 0
                }
            }
        }
    }

    func play(rate: Double) {
        guard let player else { return }
        if let item = player.currentItem, item.status == .failed {
            AppLog.editor.error(
                "play skipped, item failed error=\(item.error?.localizedDescription ?? "unknown", privacy: .public)"
            )
            return
        }
        // playImmediately 在 item 尚未 ready 时也会排队；比直接 play 更适合导入后立刻点播放。
        player.playImmediately(atRate: Float(max(0.25, rate)))
    }

    func pause() {
        player?.pause()
    }

    func seek(to seconds: TimeInterval) {
        guard let player else { return }

        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func setRate(_ rate: Double) {
        guard let player, player.timeControlStatus == .playing else { return }
        player.rate = Float(rate)
    }

    func clear() {
        cleanupPlayer()
        loadedURL = nil
        mediaDuration = 0
        isReadyToPlay = false
    }

    deinit {
        cleanupPlayer()
    }

    private func cleanupPlayer() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil

        statusObserver?.invalidate()
        statusObserver = nil

        player?.pause()
        player = nil
        isReadyToPlay = false
    }
}
