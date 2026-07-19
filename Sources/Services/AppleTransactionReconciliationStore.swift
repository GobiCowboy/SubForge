import Foundation

enum AppleTransactionReconciliationStore {
    private static let storageKey = "apple.reconciled-transaction-ids.v1"
    private static let maximumStoredIDs = 200

    static func reconciledIDs(defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: storageKey) ?? [])
    }

    static func markReconciled(_ transactionID: String, defaults: UserDefaults = .standard) {
        var ids = defaults.stringArray(forKey: storageKey) ?? []
        ids.removeAll { $0 == transactionID }
        ids.append(transactionID)
        if ids.count > maximumStoredIDs {
            ids.removeFirst(ids.count - maximumStoredIDs)
        }
        defaults.set(ids, forKey: storageKey)
    }
}
