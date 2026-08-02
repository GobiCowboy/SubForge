import Foundation

enum VersionContentRuntime {
    static let appID = "com.jago.subforge"
    static let manifestURL = URL(string: "https://gobicowboy.cn/projects/subforge/content/manifest.json")!
    static let projectURL = URL(string: "https://gobicowboy.cn/projects/subforge/")!

    static var appVersion: AppVersion {
        let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        return AppVersion(value) ?? AppVersion("1.0.0")!
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
