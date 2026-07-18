import Foundation
import Security

enum KeychainStore {
    enum Account: String {
        case cloudASRKey = "cloud-asr-key"
        case cloudLLMKey = "cloud-llm-key"
        case officialServiceKey = "official-service-key"
    }

    private static let service = Bundle.main.bundleIdentifier ?? "com.jago.subforge"

    static func read(_ account: Account) -> String? {
        var query = baseQuery(account)
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

        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ value: String, account: Account) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            delete(account)
            return false
        }

        let attributes = [kSecValueData as String: data]
        let updateQuery = baseQuery(account)
        let status = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess {
            return true
        }

        if status != errSecItemNotFound {
            SecItemDelete(baseQuery(account) as CFDictionary)
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
        return addStatus == errSecSuccess
    }

    static func delete(_ account: Account) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }

    private static func baseQuery(_ account: Account) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue
        ]
    }
}
