import AVFoundation
import Foundation

struct OfficialSmartProgressUpdate: Sendable {
    enum Phase: Sendable, Equatable {
        case securingUpload
        case uploading
        case transcribing
        case proofreading
        case finishing
    }

    let phase: Phase
    let progress: Double
}

enum OfficialSmartServiceError: LocalizedError {
    case unavailable
    case keyMissing
    case invalidResponse
    case insufficientCredits
    case activeTaskExists
    case transientService(Int)
    case uploadFailed(Int)
    case taskFailed(String)
    case additionalCreditsRequired(Int)
    case fileUnreadable
    case timeout
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unavailable: "当前区域的智能服务尚未开放"
        case .keyMissing: "尚未购买智能字幕时长"
        case .invalidResponse: "智能服务返回了无效数据"
        case .insufficientCredits: "智能字幕剩余时长不足，请先购买"
        case .activeTaskExists: "已有一个智能字幕任务在处理，请稍后再试"
        case .transientService(let status): "智能字幕服务暂时不可用（HTTP \(status)）"
        case .uploadFailed(let status): "音频直传失败（HTTP \(status)）"
        case .taskFailed(let code): "智能字幕处理失败：\(code)"
        case .additionalCreditsRequired(let seconds): "实际时长超出预估，还需 \(seconds) 秒额度"
        case .fileUnreadable: "无法读取音频文件的大小或时长"
        case .timeout: "智能字幕处理超时，任务可能仍在服务端继续"
        case .cancelled: "智能字幕任务已取消"
        }
    }
}

struct OfficialSmartWallet: Decodable {
    let balanceSeconds: Int
}

private struct SmartAPIError: Decodable {
    let error: String
}

struct SmartUploadSession: Decodable {
    struct Upload: Decodable {
        let host: URL
        let objectKey: String
        let accessKeyId: String
        let policy: String
        let signature: String
        let objectAcl: String
        let forbidOverwrite: String
        let expiresAt: String
        let maxFileSizeMb: Int
    }

    let taskId: String
    let upload: Upload
}

private struct SmartTaskResponse: Decodable {
    struct Result: Decodable {
        struct Segment: Decodable {
            let start: TimeInterval
            let end: TimeInterval
            let text: String
        }

        let segments: [Segment]
        let actualSeconds: Int
    }

    let status: String
    let errorCode: String?
    let shortfallSeconds: Int?
    let result: Result?
}

struct OfficialSmartServiceClient {
    let profile: OfficialServiceProfile
    let apiKey: String
    var session: URLSession = .shared
    var onProgress: (@Sendable (OfficialSmartProgressUpdate) -> Void)?

    func wallet() async throws -> OfficialSmartWallet {
        try await request(path: "subtitle-smart/wallet", method: "GET", body: nil)
    }

    func process(audioURL: URL, language: String) async throws -> [SubtitleSegment] {
        let cancellation = OfficialSmartCancellationContext(
            baseURL: profile.modelBaseURL,
            apiKey: apiKey,
            session: session
        )
        return try await withTaskCancellationHandler {
            try await performProcess(audioURL: audioURL, language: language, cancellation: cancellation)
        } onCancel: {
            Task { await cancellation.cancelIfNeeded() }
        }
    }

    private func performProcess(
        audioURL: URL,
        language: String,
        cancellation: OfficialSmartCancellationContext
    ) async throws -> [SubtitleSegment] {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OfficialSmartServiceError.keyMissing
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: audioURL.path)
        guard let size = (attributes?[.size] as? NSNumber)?.intValue, size > 0 else {
            throw OfficialSmartServiceError.fileUnreadable
        }
        let asset = AVURLAsset(url: audioURL)
        guard let duration = try? await asset.load(.duration).seconds,
              duration.isFinite, duration > 0 else {
            throw OfficialSmartServiceError.fileUnreadable
        }
        let uploadBody: [String: Any] = [
            "fileName": audioURL.lastPathComponent,
            "fileSizeBytes": size,
            "estimatedDurationSeconds": Int(ceil(duration)),
            "language": Self.providerLanguage(language),
            "processingRegion": profile.processingRegion
        ]
        onProgress?(.init(phase: .securingUpload, progress: 0.24))
        let body = try JSONSerialization.data(withJSONObject: uploadBody)
        let upload: SmartUploadSession = try await request(
            path: "subtitle-smart/uploads", method: "POST", body: body,
            requestID: UUID().uuidString.lowercased()
        )
        await cancellation.register(taskID: upload.taskId)
        onProgress?(.init(phase: .uploading, progress: 0.32))
        try await OSSMultipartUploader.upload(audioURL: audioURL, policy: upload.upload, session: session)
        try Task.checkCancellation()
        onProgress?(.init(phase: .transcribing, progress: 0.48))
        let submitBody = try JSONSerialization.data(withJSONObject: ["ossUrl": "oss://\(upload.upload.objectKey)"])
        let _: SmartTaskResponse = try await request(
            path: "subtitle-smart/tasks/\(upload.taskId)/submit", method: "POST", body: submitBody
        )
        return try await poll(taskID: upload.taskId)
    }

    private func poll(taskID: String) async throws -> [SubtitleSegment] {
        for attempt in 0..<300 {
            try Task.checkCancellation()
            let task: SmartTaskResponse
            do {
                task = try await request(
                    path: "subtitle-smart/tasks/\(taskID)", method: "GET", body: nil
                )
            } catch {
                guard Self.shouldRetryPolling(error) else { throw error }
                AppLog.transcription.warning(
                    "official task poll transient; retrying attempt=\(attempt + 1, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                let progress = min(0.88, 0.50 + Double(attempt) * 0.012)
                onProgress?(.init(phase: .transcribing, progress: min(progress, 0.76)))
                try await Task.sleep(for: .seconds(2))
                continue
            }
            switch task.status {
            case "completed":
                onProgress?(.init(phase: .finishing, progress: 0.92))
                guard let segments = task.result?.segments, !segments.isEmpty else {
                    throw OfficialSmartServiceError.invalidResponse
                }
                return segments.map { SubtitleSegment(start: $0.start, end: $0.end, text: $0.text) }
            case "proofreading":
                onProgress?(.init(phase: .proofreading, progress: min(0.90, 0.78 + Double(attempt) * 0.008)))
                try await Task.sleep(for: .seconds(2))
            case "cancelled":
                throw OfficialSmartServiceError.cancelled
            case "awaiting_balance":
                throw OfficialSmartServiceError.additionalCreditsRequired(task.shortfallSeconds ?? 1)
            case "failed", "expired":
                throw OfficialSmartServiceError.taskFailed(task.errorCode ?? task.status)
            default:
                let progress = min(0.76, 0.50 + Double(attempt) * 0.009)
                onProgress?(.init(phase: .transcribing, progress: progress))
                try await Task.sleep(for: .seconds(2))
            }
        }
        throw OfficialSmartServiceError.timeout
    }

    static func shouldRetryPolling(_ error: Error) -> Bool {
        if case OfficialSmartServiceError.transientService = error {
            return true
        }
        guard let urlError = error as? URLError else { return false }
        return [
            .timedOut,
            .cannotFindHost,
            .cannotConnectToHost,
            .networkConnectionLost,
            .dnsLookupFailed,
            .notConnectedToInternet,
            .secureConnectionFailed
        ].contains(urlError.code)
    }

    private func request<T: Decodable>(
        path: String,
        method: String,
        body: Data?,
        requestID: String? = nil
    ) async throws -> T {
        let url = profile.modelBaseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let requestID { request.setValue(requestID, forHTTPHeaderField: "X-Request-Id") }
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        request.httpBody = body
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OfficialSmartServiceError.invalidResponse
        }
        if (500..<600).contains(http.statusCode) {
            throw OfficialSmartServiceError.transientService(http.statusCode)
        }
        guard (200..<300).contains(http.statusCode) else {
            let code = (try? JSONDecoder().decode(SmartAPIError.self, from: data).error) ?? "HTTP_\(http.statusCode)"
            switch code {
            case "INSUFFICIENT_CREDITS": throw OfficialSmartServiceError.insufficientCredits
            case "ACTIVE_TASK_EXISTS": throw OfficialSmartServiceError.activeTaskExists
            default: throw OfficialSmartServiceError.taskFailed(code)
            }
        }
        guard let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            throw OfficialSmartServiceError.invalidResponse
        }
        return decoded
    }

    static func providerLanguage(_ language: String) -> String {
        let first = language.split(separator: ",").first.map(String.init) ?? language
        return first.split(separator: "-").first.map(String.init) ?? "zh"
    }

    static func progressPhase(forTaskStatus status: String) -> OfficialSmartProgressUpdate.Phase? {
        switch status {
        case "submitted", "processing": .transcribing
        case "proofreading": .proofreading
        case "completed": .finishing
        default: nil
        }
    }
}

private actor OfficialSmartCancellationContext {
    private let baseURL: URL
    private let apiKey: String
    private let session: URLSession
    private var taskID: String?
    private var cancellationRequested = false

    init(baseURL: URL, apiKey: String, session: URLSession) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
    }

    func register(taskID: String) async {
        self.taskID = taskID
        if cancellationRequested {
            await sendCancel(taskID: taskID)
        }
    }

    func cancelIfNeeded() async {
        cancellationRequested = true
        guard let taskID else { return }
        await sendCancel(taskID: taskID)
    }

    private func sendCancel(taskID: String) async {
        var request = URLRequest(
            url: baseURL.appending(path: "subtitle-smart/tasks/\(taskID)/cancel")
        )
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        do {
            let (_, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            AppLog.transcription.info(
                "official task cancellation requested task=\(taskID, privacy: .public) status=\(status, privacy: .public)"
            )
        } catch {
            AppLog.transcription.warning(
                "official task cancellation not confirmed task=\(taskID, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }
}

final class OfficialSmartSubtitleProvider: TranscriptionProvider {
    private let segmentationConfiguration: SubtitleSegmentationConfiguration
    private let onProgress: (@Sendable (OfficialSmartProgressUpdate) -> Void)?

    init(
        segmentationConfiguration: SubtitleSegmentationConfiguration = .init(maxCharacters: 24),
        onProgress: (@Sendable (OfficialSmartProgressUpdate) -> Void)? = nil
    ) {
        self.segmentationConfiguration = segmentationConfiguration
        self.onProgress = onProgress
    }

    func transcribe(audioURL: URL, language: String) async throws -> [SubtitleSegment] {
        guard let key = KeychainStore.read(.officialServiceKey) else {
            throw OfficialSmartServiceError.keyMissing
        }
        let segments = try await OfficialSmartServiceClient(
            profile: OfficialServiceConfiguration.activeProfile,
            apiKey: key,
            onProgress: onProgress
        ).process(audioURL: audioURL, language: language)
        return Self.applySegmentation(segments, configuration: segmentationConfiguration)
    }

    static func applySegmentation(
        _ segments: [SubtitleSegment],
        configuration: SubtitleSegmentationConfiguration
    ) -> [SubtitleSegment] {
        TimedSubtitleSegmenter.segmentEstimated(segments, configuration: configuration)
    }
}
