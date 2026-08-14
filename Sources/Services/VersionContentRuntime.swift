import Foundation

enum VersionContentRuntime {
    static let appID = "com.jago.subforge"
    static let manifestURL = URL(string: "https://gobicowboy.cn/projects/subforge/content/manifest.json")!
    static let projectURL = URL(string: "https://gobicowboy.cn/projects/subforge/")!

    static func isAllowedContentURL(_ url: URL) -> Bool {
        guard url.scheme == "https",
              let host = url.host?.lowercased(),
              let contentHost = manifestURL.host?.lowercased() else {
            return false
        }

        return host == contentHost || host.hasSuffix(".\(contentHost)")
    }

    static func appStoreURL(for url: URL) -> URL? {
        guard url.scheme == "https",
              url.host?.lowercased() == "apps.apple.com" else {
            return nil
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "macappstore"
        return components?.url
    }

    static var appVersion: AppVersion {
        let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.8"
        return AppVersion(value) ?? AppVersion("1.0.8")!
    }

    static var distributionChannel: AppDistributionChannel {
        if let declared = Bundle.main.object(forInfoDictionaryKey: "SubForgeSigningChannel") as? String {
            switch declared {
            case AppDistributionChannel.appStore.rawValue:
                return .appStore
            case AppDistributionChannel.developerID.rawValue:
                return .developerID
            case AppDistributionChannel.local.rawValue:
                return .local
            default:
                break
            }
        }

        if let receiptURL = Bundle.main.appStoreReceiptURL,
           FileManager.default.fileExists(atPath: receiptURL.path) {
            return .appStore
        }
        return .developerID
    }
}
