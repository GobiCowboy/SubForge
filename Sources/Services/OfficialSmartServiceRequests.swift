import AVFoundation
import Foundation

extension OfficialSmartServiceClient {
    func poll(taskID: String) async throws -> [SubtitleSegment] {
        var observedProofreading = false
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
                guard let result = task.result else {
                    throw OfficialSmartServiceError.invalidResponse
                }
                guard result.proofreadingApplied else {
                    throw OfficialSmartServiceError.proofreadingNotApplied
                }
                guard !result.segments.isEmpty else {
                    throw OfficialSmartServiceError.invalidResponse
                }
                if !observedProofreading {
                    onProgress?(.init(phase: .proofreading, progress: 0.88))
                    try await Task.sleep(for: .milliseconds(500))
                }
                onProgress?(.init(phase: .finishing, progress: 0.92))
                return result.segments.map { segment in
                    SubtitleSegment(
                        start: segment.start,
                        end: segment.end,
                        text: segment.text,
                        words: segment.words?.map {
                            SubtitleWord(start: $0.start, end: $0.end, text: $0.text)
                        }
                    )
                }
            case "proofreading":
                observedProofreading = true
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

    func request<T: Decodable>(
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
        guard (200..<300).contains(http.statusCode) else {
            throw Self.mapHTTPError(statusCode: http.statusCode, data: data)
        }
        guard let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            throw OfficialSmartServiceError.invalidResponse
        }
        return decoded
    }

    static func mapHTTPError(statusCode: Int, data: Data) -> OfficialSmartServiceError {
        let response = try? JSONDecoder().decode(SmartAPIError.self, from: data)
        let code = response?.error ?? "HTTP_\(statusCode)"
        switch code {
        case "INSUFFICIENT_CREDITS": return .insufficientCredits
        case "ACTIVE_TASK_EXISTS": return .activeTaskExists
        case "ASR_SUBMIT_TEMPORARILY_UNAVAILABLE":
            return .upstreamTemporarilyUnavailable(
                reservationReleased: response?.reservationReleased == true
            )
        case "ASR_SUBMIT_REJECTED":
            return .upstreamSubmissionRejected(
                reservationReleased: response?.reservationReleased == true
            )
        default:
            if (500..<600).contains(statusCode) {
                return .transientService(statusCode)
            }
            return .taskFailed(code)
        }
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

actor OfficialSmartCancellationContext {
    let baseURL: URL
    let apiKey: String
    let session: URLSession
    var taskID: String?
    var cancellationRequested = false

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

    func sendCancel(taskID: String) async {
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
