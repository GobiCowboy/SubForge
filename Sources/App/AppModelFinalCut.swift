import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

extension AppModel {
    func importIntoFinalCutPro(_ fcpxmlURL: URL) throws {
        let attempts: [[String]] = [
            ["-b", "com.apple.FinalCutApp", fcpxmlURL.path],
            ["-b", "com.apple.FinalCut", fcpxmlURL.path]
        ] + finalCutProApplicationURLs().map { ["-a", $0.path, fcpxmlURL.path] } + [
            [fcpxmlURL.path]
        ]

        var failureMessages: [String] = []
        for arguments in attempts {
            do {
                try runOpenCommand(arguments: arguments)
                return
            } catch {
                failureMessages.append(error.localizedDescription)
            }
        }

        throw NSError(
            domain: "SubForge.FinalCutProImport",
            code: 2,
            userInfo: [
                NSLocalizedDescriptionKey: failureMessages.last
                    ?? "无法发现 Final Cut Pro 或打开 FCPXML。"
            ]
        )
    }

    func finalCutProApplicationURLs() -> [URL] {
        let workspace = NSWorkspace.shared
        let bundleURLs = [
            workspace.urlForApplication(withBundleIdentifier: "com.apple.FinalCutApp"),
            workspace.urlForApplication(withBundleIdentifier: "com.apple.FinalCut")
        ].compactMap(\.self)

        let pathURLs = [
            "/Applications/Final Cut Pro Creator Studio.app",
            "/Applications/Final Cut Pro.app"
        ].map { URL(fileURLWithPath: $0, isDirectory: true) }

        var seen = Set<String>()
        return (bundleURLs + pathURLs).filter { url in
            guard FileManager.default.fileExists(atPath: url.path) else { return false }
            return seen.insert(url.standardizedFileURL.path).inserted
        }
    }

    func runOpenCommand(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments

        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(
                domain: "SubForge.FinalCutProImport",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message?.isEmpty == false ? message! : "无法打开 Final Cut Pro 或导入 FCPXML。"]
            )
        }
    }

    func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
