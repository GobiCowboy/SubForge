import SwiftUI
import UniformTypeIdentifiers

extension HomeView {
    func handleProviders(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL? = {
                if let data = item as? Data {
                    return URL(dataRepresentation: data, relativeTo: nil)
                }
                if let url = item as? URL {
                    return url
                }
                if let path = item as? String {
                    return URL(fileURLWithPath: path)
                }
                return nil
            }()
            guard let url else { return }

            Task { @MainActor in
                // 保留 drop 返回的原始 URL；importDocument 内 SecurityScopedResourceAccess 会 startAccessing。
                // 不要 standardizedFileURL，否则可能丢掉 security-scoped 令牌，导致后续无法播放。
                model.importDocument(at: url)
            }
        }
        return true
    }

    func iconName(for kind: String) -> String {
        switch kind {
        case "audio":
            return "waveform"
        default:
            return "doc.text"
        }
    }

    var watchState: (color: Color, isAnimated: Bool) {
        let watch = model.settings.watchSettings

        guard !watch.directoryPath.isEmpty else {
            return (.gray, false)
        }

        if model.isWatchingDirectory {
            return (.green, true)
        }

        return (.blue, true)
    }
}
