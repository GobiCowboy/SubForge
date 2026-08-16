import AppKit
import Foundation

extension AppModel {
    struct ExportDirectoryChoice {
        let url: URL
        let access: SecurityScopedResourceAccess?
    }

    func chooseExportDirectory() -> ExportDirectoryChoice? {
        switch settings.exportSettings.saveLocation {
        case .sameAsSource:
            if let directory = currentDocumentURL?.deletingLastPathComponent() {
                if let access = SecurityScopedResourceAccess(
                    bookmarkData: settings.exportSettings.sourceOutputBookmarkData,
                    fallbackPath: settings.exportSettings.sourceOutputPath,
                    isDirectory: true
                ), access.hasAccess,
                   directoryIsInside(directory, root: access.url) {
                    return ExportDirectoryChoice(url: directory, access: access)
                }
                return ExportDirectoryChoice(
                    url: directory,
                    access: SecurityScopedResourceAccess(url: directory)
                )
            }
            return askForExportDirectory()
        case .customFolder:
            let path = settings.exportSettings.customOutputPath
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty {
                guard let access = SecurityScopedResourceAccess(
                    bookmarkData: settings.exportSettings.customOutputBookmarkData,
                    fallbackPath: path,
                    isDirectory: true
                ) else {
                    return nil
                }
                return ExportDirectoryChoice(url: access.url, access: access)
            }
            return askForExportDirectory()
        }
    }

    func authorizeSourceExportDirectory(_ sourceDirectory: URL) -> ExportDirectoryChoice? {
        let authorizationRoot = sourceDirectory.deletingLastPathComponent()
        var authorizedRoot: URL?

        while authorizedRoot == nil {
            guard let selectedDirectory = ExportDirectoryAuthorization.requestAccess(
                to: authorizationRoot
            ) else {
                return nil
            }
            if directoryIsInside(sourceDirectory, root: selectedDirectory) {
                authorizedRoot = selectedDirectory
            } else {
                let shouldRetry = ExportDirectoryAuthorization.presentInvalidSelection(
                    selectedDirectory: selectedDirectory,
                    requiredSourceDirectory: sourceDirectory
                )
                guard shouldRetry else { return nil }
            }
        }

        guard let authorizedRoot else { return nil }
        var updated = settings
        updated.exportSettings.sourceOutputPath = authorizedRoot.path
        updated.exportSettings.sourceOutputBookmarkData =
            SecurityScopedResourceAccess.bookmarkData(for: authorizedRoot)
        settings = updated

        return ExportDirectoryChoice(
            url: sourceDirectory,
            access: SecurityScopedResourceAccess(url: authorizedRoot)
        )
    }

    func directoryIsInside(_ directory: URL, root: URL) -> Bool {
        let directoryPath = directory.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        return directoryPath == rootPath || directoryPath.hasPrefix(rootPath + "/")
    }

    func isFileWritePermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == NSFileWriteNoPermissionError {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain,
           (nsError.code == Int(EACCES) || nsError.code == Int(EPERM)) {
            return true
        }
        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isFileWritePermissionError(underlyingError)
        }
        return false
    }

    func askForExportDirectory() -> ExportDirectoryChoice? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "导出到此处"
        panel.message = "选择导出目录"

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return ExportDirectoryChoice(
            url: url,
            access: SecurityScopedResourceAccess(url: url)
        )
    }
}
