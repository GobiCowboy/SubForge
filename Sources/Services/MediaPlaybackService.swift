import AVFoundation
import Foundation

final class MediaPlaybackService {
    var onTimeUpdate: ((TimeInterval) -> Void)?
    var onPlaybackFinished: (() -> Void)?
    var onDurationLoaded: ((TimeInterval) -> Void)?

    private(set) var mediaDuration: TimeInterval = 0

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var loadedURL: URL?

    var hasLoadedMedia: Bool {
        player != nil
    }

    func loadMedia(from url: URL?) {
        guard loadedURL != url else { return }

        cleanupPlayer()
        loadedURL = url
        mediaDuration = 0

        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.volume = 1
        self.player = player

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
                await MainActor.run {
                    self.mediaDuration = 0
                }
            }
        }
    }

    func play(rate: Double) {
        guard let player else { return }
        player.playImmediately(atRate: Float(rate))
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

        player?.pause()
        player = nil
    }
}
