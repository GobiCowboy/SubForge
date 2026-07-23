import AVFoundation
import Foundation
import Speech

final class CloudASRProvider: TranscriptionProvider {
    let apiURL: String
    let apiKey: String
    let model: String
    let segmentationConfiguration: SubtitleSegmentationConfiguration

    init(
        apiURL: String,
        apiKey: String,
        model: String,
        segmentationConfiguration: SubtitleSegmentationConfiguration
    ) {
        self.apiURL = apiURL
        self.apiKey = apiKey
        self.model = model
        self.segmentationConfiguration = segmentationConfiguration
    }

    func transcribe(audioURL: URL, language: String) async throws -> [SubtitleSegment] {
        AppLog.transcription.info(
            "cloudASR configuration urlValid=\(Self.validatedEndpoint(self.apiURL) != nil, privacy: .public) keyPresent=\(!self.apiKey.isEmpty, privacy: .public) modelPresent=\(!self.model.isEmpty, privacy: .public) model=\(self.model, privacy: .public)"
        )
        guard !apiKey.isEmpty else {
            throw TranscriptionError.cloudNotConfigured
        }

        // 与 Git 一致：qwen3-asr-flash-filetrans / transcription 端点 → 异步 filetrans
        // filetrans 不能走 OpenAI compatible-mode（会 404 model_not_supported）
        if usesFiletransModel || isDashScopeAsyncURL {
            guard Self.validatedEndpoint(asyncTranscriptionURL) != nil else {
                throw TranscriptionError.cloudNotConfigured
            }
            return try await transcribeDashScopeAsync(audioURL: audioURL, language: language)
        }

        guard Self.validatedEndpoint(apiURL) != nil else {
            throw TranscriptionError.cloudNotConfigured
        }

        if isDashScopeCompatibleModeURL {
            return try await transcribeDashScopeCompatible(audioURL: audioURL, language: language)
        }

        return try await transcribeWhisperCompatible(audioURL: audioURL, language: language)
    }

    static func validatedEndpoint(_ rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains("{WorkspaceId}"),
              !trimmed.contains("{workspaceId}"),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host,
              !host.isEmpty,
              !host.contains("{"),
              !host.contains("}") else {
            return nil
        }
        return url
    }

    var usesFiletransModel: Bool {
        model.lowercased().contains("filetrans")
    }

    var isDashScopeCompatibleModeURL: Bool {
        guard let url = URL(string: apiURL) else { return false }
        return url.path.hasSuffix("/compatible-mode/v1/chat/completions")
    }

    var isDashScopeAsyncURL: Bool {
        guard let url = URL(string: apiURL) else { return false }
        return url.path.hasSuffix("/api/v1/services/audio/asr/transcription")
    }

    /// Git 异步端点：.../api/v1/services/audio/asr/transcription
    /// 若设置里误填了 compatible-mode，按同 host 改回 transcription 路径。
    var asyncTranscriptionURL: String {
        if isDashScopeAsyncURL {
            return apiURL
        }
        if let url = URL(string: apiURL), let host = url.host, !host.isEmpty {
            let scheme = (url.scheme?.isEmpty == false) ? url.scheme! : "https"
            return "\(scheme)://\(host)/api/v1/services/audio/asr/transcription"
        }
        return "https://dashscope.aliyuncs.com/api/v1/services/audio/asr/transcription"
    }
}
