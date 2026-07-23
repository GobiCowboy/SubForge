import AVFoundation
import Foundation
import Speech

extension CloudASRProvider {
    func uploadLocalAudioToDashScopeTempStorage(audioURL: URL) async throws -> String {
        let policy = try await fetchDashScopeUploadPolicy()

        guard let uploadHost = policy["upload_host"] as? String,
              let uploadDir = policy["upload_dir"] as? String,
              let accessKeyId = policy["oss_access_key_id"] as? String,
              let signature = policy["signature"] as? String,
              let policyToken = policy["policy"] as? String,
              let objectACL = policy["x_oss_object_acl"] as? String,
              let forbidOverwrite = policy["x_oss_forbid_overwrite"] as? String,
              let uploadHostURL = URL(string: uploadHost)
        else {
            throw TranscriptionError.cloudRequestFailedWithDetail("DashScope 上传凭证字段不完整")
        }

        let originalName = audioURL.lastPathComponent
        let safeName = originalName.isEmpty ? "audio.m4a" : originalName
        // 避免同名冲突（x-oss-forbid-overwrite 常为 true）
        let objectName = "subforge-\(UUID().uuidString.lowercased())-\(safeName)"
        let objectKey = "\(uploadDir)/\(objectName)"

        let fileData = try Data(contentsOf: audioURL)
        if let maxMB = Self.intValue(policy["max_file_size_mb"]), maxMB > 0 {
            let maxBytes = maxMB * 1024 * 1024
            if fileData.count > maxBytes {
                throw TranscriptionError.cloudRequestFailedWithDetail(
                    "音频文件过大（\(Self.formatByteCount(fileData.count))），当前模型临时上传上限约 \(maxMB)MB"
                )
            }
        }

        let boundary = "----SubForgeDashScope-\(UUID().uuidString)"
        var body = Data()

        func appendTextField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        // 官方要求 file 必须是最后一个表单域
        appendTextField("OSSAccessKeyId", accessKeyId)
        appendTextField("Signature", signature)
        appendTextField("policy", policyToken)
        appendTextField("x-oss-object-acl", objectACL)
        appendTextField("x-oss-forbid-overwrite", forbidOverwrite)
        appendTextField("key", objectKey)
        appendTextField("success_action_status", "200")

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(objectName)\"\r\n".data(using: .utf8)!
        )
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: uploadHostURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 300

        AppLog.transcription.info(
            "cloudASR tempUpload bytes=\(fileData.count, privacy: .public) keySuffix=\(objectName, privacy: .public)"
        )

        let (responseData, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard code == 200 else {
            let message = String(data: responseData, encoding: .utf8) ?? ""
            throw TranscriptionError.cloudRequestFailedWithDetail(
                "DashScope 临时上传失败 HTTP \(code): \(message.prefix(200))"
            )
        }

        return "oss://\(objectKey)"
    }

    func fetchDashScopeUploadPolicy() async throws -> [String: Any] {
        let candidates = dashScopeUploadPolicyEndpointCandidates()
        var lastError: String = "未知错误"

        for endpoint in candidates {
            var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
            components?.queryItems = [
                URLQueryItem(name: "action", value: "getPolicy"),
                URLQueryItem(name: "model", value: model)
            ]
            guard let url = components?.url else { continue }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 60

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                guard code == 200 else {
                    lastError = "HTTP \(code): \(String(data: data, encoding: .utf8) ?? "")"
                    AppLog.transcription.error(
                        "cloudASR getPolicy failed endpoint=\(url.absoluteString, privacy: .public) \(lastError, privacy: .public)"
                    )
                    continue
                }

                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let policy = json["data"] as? [String: Any]
                else {
                    lastError = "响应缺少 data 字段"
                    continue
                }

                AppLog.transcription.info(
                    "cloudASR getPolicy ok endpoint=\(url.absoluteString, privacy: .public)"
                )
                return policy
            } catch {
                lastError = error.localizedDescription
            }
        }

        throw TranscriptionError.cloudRequestFailedWithDetail(
            "获取 DashScope 上传凭证失败：\(lastError.prefix(200))"
        )
    }

    /// 优先用设置里的业务空间域名，失败再回退公共 dashscope 域名。
    func dashScopeUploadPolicyEndpointCandidates() -> [URL] {
        var urls: [URL] = []
        if let requestURL = URL(string: asyncTranscriptionURL),
           let host = requestURL.host,
           !host.isEmpty {
            let scheme = (requestURL.scheme?.isEmpty == false) ? requestURL.scheme! : "https"
            if let url = URL(string: "\(scheme)://\(host)/api/v1/uploads") {
                urls.append(url)
            }
        }

        let fallbacks = [
            "https://dashscope.aliyuncs.com/api/v1/uploads",
            "https://dashscope-intl.aliyuncs.com/api/v1/uploads"
        ]
        for raw in fallbacks {
            if let url = URL(string: raw), !urls.contains(url) {
                urls.append(url)
            }
        }
        return urls
    }

    static func formatByteCount(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let number as Int:
            return number
        case let number as NSNumber:
            return number.intValue
        case let text as String:
            return Int(text)
        default:
            return nil
        }
    }
}
