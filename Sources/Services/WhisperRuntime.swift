import AVFoundation
import Foundation
import Speech

extension WhisperCppProvider {
    func resolveCLIPath() throws -> String {
        if let path = WhisperRuntime.cliCandidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            return path
        }

        throw TranscriptionError.cliUnavailable
    }

    func resolveModelPath() throws -> String {
        if let requestedPath = WhisperModelStore.existingPath(for: model)?.path {
            return requestedPath
        }

        if let availableModel = WhisperModelStore.availableModels().first {
            if let availablePath = WhisperModelStore.existingPath(for: availableModel)?.path {
                return availablePath
            }
        }

        throw TranscriptionError.modelUnavailable
    }

    static func convertToWAV(input: URL, output: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        process.arguments = [
            "-f", "WAVE",
            "-d", "LEI16@16000",
            "-c", "1",
            input.path,
            output.path
        ]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw TranscriptionError.audioConversionFailed
        }
    }

    static func leadingAudibleOffset(in wavURL: URL) throws -> TimeInterval {
        let file = try AVAudioFile(forReading: wavURL)
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        guard sampleRate > 0 else { return 0 }

        let windowFrames = max(1, Int(sampleRate * 0.08))
        let chunkSize: AVAudioFrameCount = 4096
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkSize) else {
            return 0
        }

        var windowEnergy: Double = 0
        var windowFrameCount = 0
        var windowRMSValues: [Double] = []

        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: chunkSize)
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0, let channels = buffer.floatChannelData else { break }
            let channelCount = Int(format.channelCount)

            for frameIndex in 0..<frameLength {
                var sum: Double = 0
                for channelIndex in 0..<channelCount {
                    let sample = Double(channels[channelIndex][frameIndex])
                    sum += sample * sample
                }

                windowEnergy += sum / Double(max(channelCount, 1))
                windowFrameCount += 1

                if windowFrameCount >= windowFrames {
                    windowRMSValues.append(sqrt(windowEnergy / Double(windowFrameCount)))
                    windowEnergy = 0
                    windowFrameCount = 0
                }
            }
        }

        if windowFrameCount > 0 {
            windowRMSValues.append(sqrt(windowEnergy / Double(windowFrameCount)))
        }

        guard !windowRMSValues.isEmpty else { return 0 }

        let baselineWindowCount = min(windowRMSValues.count, max(1, Int(3.0 / 0.08)))
        let baseline = Array(windowRMSValues.prefix(baselineWindowCount)).sorted()
        let baselineRMS = baseline[baseline.count / 2]
        let speechThreshold = max(0.012, baselineRMS * 5.0)
        let requiredWindows = 3
        var runLength = 0
        var candidateIndex: Int?

        for (index, rms) in windowRMSValues.enumerated() {
            if rms >= speechThreshold {
                if candidateIndex == nil {
                    candidateIndex = index
                }
                runLength += 1

                if runLength >= requiredWindows, let candidateIndex {
                    let offset = Double(candidateIndex * windowFrames) / sampleRate
                    AppLog.transcription.info(
                        "whisperLeadingSpeechOffset offset=\(offset, privacy: .public) threshold=\(speechThreshold, privacy: .public) baseline=\(baselineRMS, privacy: .public)"
                    )
                    return max(0, offset)
                }
            } else {
                candidateIndex = nil
                runLength = 0
            }
        }

        AppLog.transcription.info(
            "whisperLeadingSpeechOffset offset=0 threshold=\(speechThreshold, privacy: .public) baseline=\(baselineRMS, privacy: .public)"
        )
        return 0
    }
}
