import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

extension AppModel {
    func makeExportPlan(baseName: String, directory: URL) -> ExportPlan {
        let needsFCPXML = settings.exportSettings.exportToFinalCutPro
        let format = settings.exportSettings.format

        let srtURL = shouldExportSRT(format)
            ? exportURL(directory: directory, baseName: baseName, extensionName: "srt")
            : nil
        let fcpxmlURL = (shouldExportFCPXML(format) || needsFCPXML)
            ? exportURL(directory: directory, baseName: baseName, extensionName: "fcpxml")
            : nil

        return ExportPlan(
            srtURL: srtURL,
            fcpxmlURL: fcpxmlURL,
            summary: exportSummary(srtURL: srtURL, fcpxmlURL: fcpxmlURL)
        )
    }

    func shouldExportSRT(_ format: ExportFormat) -> Bool {
        switch format {
        case .srt, .srtAndFCPXML, .txt, .vtt:
            return true
        case .fcpxml:
            return false
        }
    }

    func shouldExportFCPXML(_ format: ExportFormat) -> Bool {
        switch format {
        case .fcpxml, .srtAndFCPXML:
            return true
        case .srt, .txt, .vtt:
            return false
        }
    }

    func exportURL(directory: URL, baseName: String, extensionName: String) -> URL {
        let proposedURL = directory.appendingPathComponent(baseName).appendingPathExtension(extensionName)
        guard !settings.exportSettings.overwriteExisting else {
            return proposedURL
        }

        var candidate = proposedURL
        var index = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(baseName)-\(index)")
                .appendingPathExtension(extensionName)
            index += 1
        }
        return candidate
    }

    func exportSummary(srtURL: URL?, fcpxmlURL: URL?) -> String {
        switch (srtURL != nil, fcpxmlURL != nil) {
        case (true, true):
            return "SRT 和 FCPXML"
        case (true, false):
            return "SRT"
        case (false, true):
            return "FCPXML"
        case (false, false):
            return "文件"
        }
    }
}
