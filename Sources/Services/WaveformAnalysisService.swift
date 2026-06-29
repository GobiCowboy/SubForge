import AVFoundation
import Foundation

enum WaveformAnalysisService {
    static func analyze(url: URL, sampleCount: Int = 180) async -> [Double] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }

        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else {
            return []
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        guard let reader = try? AVAssetReader(asset: asset) else { return [] }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else { return [] }
        reader.add(output)
        guard reader.startReading() else { return [] }

        let windowSize = 2048
        var windows: [Double] = []
        var sampleAccumulator = 0.0
        var sampleCountInWindow = 0

        while reader.status == .reading {
            guard let buffer = output.copyNextSampleBuffer(),
                  let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else {
                break
            }

            let length = CMBlockBufferGetDataLength(blockBuffer)
            guard length > 0 else { continue }

            var data = Data(count: length)
            data.withUnsafeMutableBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else { return }
                CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: baseAddress)
            }

            data.withUnsafeBytes { rawBuffer in
                let samples = rawBuffer.bindMemory(to: Int16.self)
                for sample in samples {
                    sampleAccumulator += abs(Double(sample)) / Double(Int16.max)
                    sampleCountInWindow += 1

                    if sampleCountInWindow >= windowSize {
                        windows.append(sampleAccumulator / Double(sampleCountInWindow))
                        sampleAccumulator = 0
                        sampleCountInWindow = 0
                    }
                }
            }
        }

        if sampleCountInWindow > 0 {
            windows.append(sampleAccumulator / Double(sampleCountInWindow))
        }

        guard !windows.isEmpty else { return [] }
        return downsample(windows: windows, targetCount: sampleCount)
    }

    private static func downsample(windows: [Double], targetCount: Int) -> [Double] {
        let count = min(max(targetCount, 24), max(windows.count, 24))
        let step = Double(windows.count) / Double(count)
        var samples: [Double] = []
        samples.reserveCapacity(count)

        for index in 0..<count {
            let start = Int(Double(index) * step)
            let end = min(windows.count, max(start + 1, Int(Double(index + 1) * step)))
            let slice = windows[start..<end]
            let peak = slice.max() ?? 0
            samples.append(peak)
        }

        let maxValue = max(samples.max() ?? 1, 0.0001)
        return samples.map { value in
            let normalized = value / maxValue
            return max(0.06, sqrt(normalized))
        }
    }
}
