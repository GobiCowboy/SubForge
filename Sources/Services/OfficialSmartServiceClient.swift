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
    case keychainUnavailable
    case invalidResponse
    case insufficientCredits
    case activeTaskExists
    case transientService(Int)
    case uploadFailed(Int)
    case taskFailed(String)
    case proofreadingNotApplied
    case additionalCreditsRequired(Int)
    case fileUnreadable
    case timeout
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unavailable: "当前区域的智能服务尚未开放"
        case .keyMissing: "尚未购买智能字幕时长"
        case .keychainUnavailable: "无法访问官方服务凭证，请打开正式版 App 或在系统钥匙串中允许 SubForge 访问"
        case .invalidResponse: "智能服务返回了无效数据"
        case .insufficientCredits: "智能字幕剩余时长不足，请先购买"
        case .activeTaskExists: "已有一个智能字幕任务在处理，请稍后再试"
        case .transientService(let status): "智能字幕服务暂时不可用（HTTP \(status)）"
        case .uploadFailed(let status): "音频直传失败（HTTP \(status)）"
        case .taskFailed(let code): "智能字幕处理失败：\(code)"
        case .proofreadingNotApplied: "官方智能字幕未完成 AI 校对，请稍后重试"
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

struct SmartAPIError: Decodable {
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

struct SmartTaskResponse: Decodable {
    struct Result: Decodable {
        struct Segment: Decodable {
            struct Word: Decodable {
                let start: TimeInterval
                let end: TimeInterval
                let text: String
            }

            let start: TimeInterval
            let end: TimeInterval
            let text: String
            let words: [Word]?
        }

        let segments: [Segment]
        let actualSeconds: Int
        let proofreadingApplied: Bool
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

    func process(
        audioURL: URL,
        language: String,
        proofreadingPrompt: String = ""
    ) async throws -> [SubtitleSegment] {
        let cancellation = OfficialSmartCancellationContext(
            baseURL: profile.modelBaseURL,
            apiKey: apiKey,
            session: session
        )
        return try await withTaskCancellationHandler {
            try await performProcess(
                audioURL: audioURL,
                language: language,
                proofreadingPrompt: proofreadingPrompt,
                cancellation: cancellation
            )
        } onCancel: {
            Task { await cancellation.cancelIfNeeded() }
        }
    }

    func performProcess(
        audioURL: URL,
        language: String,
        proofreadingPrompt: String,
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
        let submitBody = try Self.makeSubmitBody(
            ossURL: "oss://\(upload.upload.objectKey)",
            proofreadingPrompt: proofreadingPrompt
        )
        let _: SmartTaskResponse = try await request(
            path: "subtitle-smart/tasks/\(upload.taskId)/submit", method: "POST", body: submitBody
        )
        return try await poll(taskID: upload.taskId)
    }

    static func makeSubmitBody(
        ossURL: String,
        proofreadingPrompt: String
    ) throws -> Data {
        var payload = ["ossUrl": ossURL]
        let trimmedPrompt = proofreadingPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrompt.isEmpty {
            payload["proofreadingPrompt"] = String(trimmedPrompt.prefix(4_000))
        }
        return try JSONSerialization.data(withJSONObject: payload)
    }
}
