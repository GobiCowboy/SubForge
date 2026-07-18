import Foundation

enum OSSMultipartUploader {
    static func upload(
        audioURL: URL,
        policy: SmartUploadSession.Upload,
        session: URLSession
    ) async throws {
        guard policy.host.scheme?.lowercased() == "https",
              let host = policy.host.host?.lowercased(),
              host == "aliyuncs.com" || host.hasSuffix(".aliyuncs.com") else {
            throw OfficialSmartServiceError.invalidResponse
        }
        let boundary = "----SubForgeOfficial-\(UUID().uuidString)"
        let multipartURL = try buildMultipartFile(audioURL: audioURL, policy: policy, boundary: boundary)
        defer { try? FileManager.default.removeItem(at: multipartURL) }

        var request = URLRequest(url: policy.host)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 600
        let (_, response) = try await session.upload(for: request, fromFile: multipartURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OfficialSmartServiceError.uploadFailed((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }

    private static func buildMultipartFile(
        audioURL: URL,
        policy: SmartUploadSession.Upload,
        boundary: String
    ) throws -> URL {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("subforge-oss-\(UUID().uuidString.lowercased()).multipart")
        guard FileManager.default.createFile(atPath: temporaryURL.path, contents: nil) else {
            throw OfficialSmartServiceError.fileUnreadable
        }
        do {
            let output = try FileHandle(forWritingTo: temporaryURL)
            defer { try? output.close() }

            func write(_ text: String) throws {
                try output.write(contentsOf: Data(text.utf8))
            }
            func field(_ name: String, _ value: String) throws {
                try write("--\(boundary)\r\n")
                try write("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
                try write("\(value)\r\n")
            }

            try field("OSSAccessKeyId", policy.accessKeyId)
            try field("Signature", policy.signature)
            try field("policy", policy.policy)
            try field("x-oss-object-acl", policy.objectAcl)
            try field("x-oss-forbid-overwrite", policy.forbidOverwrite)
            try field("key", policy.objectKey)
            try field("success_action_status", "200")
            try write("--\(boundary)\r\n")
            try write("Content-Disposition: form-data; name=\"file\"; filename=\"audio.bin\"\r\n")
            try write("Content-Type: application/octet-stream\r\n\r\n")

            let input = try FileHandle(forReadingFrom: audioURL)
            defer { try? input.close() }
            while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
                try output.write(contentsOf: chunk)
            }
            try write("\r\n--\(boundary)--\r\n")
            return temporaryURL
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }
}
