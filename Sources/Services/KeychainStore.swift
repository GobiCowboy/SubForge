import Foundation
import LocalAuthentication
import Security

enum KeychainStore {
    enum Account: String {
        case cloudASRKey = "cloud-asr-key"
        case cloudLLMKey = "cloud-llm-key"
        case officialServiceKey = "official-service-key"
    }

    private static let baseService = Bundle.main.bundleIdentifier ?? "com.jago.subforge"
    private static let cacheLock = NSLock()
    private static var cachedValues: [Account: String] = [:]

    static func read(_ account: Account) -> String? {
        if let cached = cachedValue(for: account) {
            return cached
        }

        var query = nonInteractiveQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            AppLog.settings.error(
                "keychainReadFailed account=\(account.rawValue, privacy: .public) status=\(status, privacy: .public)"
            )
            return nil
        }

        guard let value = String(data: data, encoding: .utf8) else { return nil }
        cache(value, for: account)
        return value
    }

    @discardableResult
    static func save(_ value: String, account: Account) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            delete(account)
            return false
        }

        let attributes = [kSecValueData as String: data]
        let updateQuery = nonInteractiveQuery(account)
        let status = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess {
            cache(trimmed, for: account)
            return true
        }

        // Never delete an item that this signature cannot update. Deleting or
        // updating a foreign/legacy item can summon the login-keychain dialog.
        guard status == errSecItemNotFound else {
            AppLog.settings.error(
                "keychainUpdateFailed account=\(account.rawValue, privacy: .public) status=\(status, privacy: .public)"
            )
            return false
        }

        var query = baseQuery(account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus != errSecSuccess {
            AppLog.settings.error(
                "keychainSaveFailed account=\(account.rawValue, privacy: .public) status=\(addStatus, privacy: .public)"
            )
        }
        if addStatus == errSecSuccess {
            cache(trimmed, for: account)
        }
        return addStatus == errSecSuccess
    }

    static func delete(_ account: Account) {
        _ = SecItemDelete(nonInteractiveQuery(account) as CFDictionary)
        _ = cacheLock.withLock {
            cachedValues.removeValue(forKey: account)
        }
    }

    private static func baseQuery(_ account: Account) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName(for: account),
            kSecAttrAccount as String: account.rawValue
        ]
    }

    private static func nonInteractiveQuery(_ account: Account) -> [String: Any] {
        var query = baseQuery(account)
        let authenticationContext = LAContext()
        authenticationContext.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = authenticationContext
        return query
    }

    /// Development/local builds must not touch TestFlight/App Store items with
    /// the same bundle identifier. Their code-signing ACLs differ and macOS can
    /// otherwise prompt for the login-keychain password on every rebuilt app.
    /// Production keeps the legacy cloud-key service so upgrades retain keys.
    static func serviceName(for account: Account, signingChannel: String? = nil) -> String {
        let channel = signingChannel ?? currentSigningChannel
        if account == .officialServiceKey {
            return "\(baseService).official-service.v2.\(channel)"
        }
        if channel == "app-store" {
            return baseService
        }
        return "\(baseService).\(account.rawValue).v2.\(channel)"
    }

    private static var currentSigningChannel: String {
        if let declared = Bundle.main.object(forInfoDictionaryKey: "SubForgeSigningChannel") as? String,
           ["local", "development", "app-store"].contains(declared) {
            return declared
        }
        if entitlement("get-task-allow") as? Bool == true {
            return "development"
        }
        guard entitlement("com.apple.application-identifier") as? String != nil else {
            return "local"
        }
        if Bundle.main.appStoreReceiptURL.map({ FileManager.default.fileExists(atPath: $0.path) }) == true {
            return "app-store"
        }
        return "app-store"
    }

    private static func entitlement(_ name: String) -> Any? {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        return SecTaskCopyValueForEntitlement(task, name as CFString, nil)
    }

    private static func cachedValue(for account: Account) -> String? {
        cacheLock.withLock { cachedValues[account] }
    }

    private static func cache(_ value: String, for account: Account) {
        cacheLock.withLock {
            cachedValues[account] = value
        }
    }
}
