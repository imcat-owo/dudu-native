import Foundation
import Security

// MARK: - D25 · SandboxKeychain
//
// Secure storage for per-server SSH secrets (private key PEM or password).
// Same Keychain pattern the Providers stack uses (ProviderKeychainHelper):
// kSecClassGenericPassword, service namespaced to this feature, accessible
// after first unlock, iCloud-Keychain synchronizable like provider keys.
//
// Service:  com.dudu.ios.sandbox.<serverId>
// Account:  ssh-secret
//
// Hard rules (her dead rules):
// - The secret value is NEVER logged (only hit/miss + byte length).
// - The secret is NEVER written to UserDefaults / files / URLs.
// - Deleting a server wipes its secret (deleteSecret(for:)).

private let sandboxKeychainLogger = AppLogger(category: "SandboxKeychain")

enum SandboxKeychain {
    private static func service(for serverId: String) -> String {
        "com.dudu.ios.sandbox.\(serverId)"
    }

    private static let account = "ssh-secret"

    /// Save (replace) the secret for a server. Empty secrets are refused —
    /// callers keep the old secret instead (old SshConfigForm semantics).
    static func saveSecret(_ secret: String, for serverId: String) {
        guard !secret.isEmpty else { return }
        let service = service(for: serverId)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        var syncDelete = deleteQuery
        syncDelete[kSecAttrSynchronizable as String] = true
        SecItemDelete(syncDelete as CFDictionary)

        var addQuery = deleteQuery
        addQuery[kSecValueData as String] = Data(secret.utf8)
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        addQuery[kSecAttrSynchronizable as String] = true
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        // Log length only — never the value.
        sandboxKeychainLogger.info(
            "write sshSecret serverId=\(serverId.prefix(8)) secretLen=\(secret.count) status=\(status)"
        )
    }

    /// Load the secret for a server, or nil when none was saved.
    static func loadSecret(for serverId: String) -> String? {
        let service = service(for: serverId)
        let syncQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        if SecItemCopyMatching(syncQuery as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let s = String(data: data, encoding: .utf8)
        {
            sandboxKeychainLogger.info(
                "read sshSecret serverId=\(serverId.prefix(8)) src=sync hit=true secretLen=\(s.count)"
            )
            return s
        }
        let legacyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        result = nil
        guard SecItemCopyMatching(legacyQuery as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let s = String(data: data, encoding: .utf8)
        else {
            sandboxKeychainLogger.info("read sshSecret serverId=\(serverId.prefix(8)) hit=false")
            return nil
        }
        sandboxKeychainLogger.info(
            "read sshSecret serverId=\(serverId.prefix(8)) src=legacy hit=true secretLen=\(s.count)"
        )
        return s
    }

    /// Wipe the secret for a server. Called on server delete.
    static func deleteSecret(for serverId: String) {
        let service = service(for: serverId)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let s1 = SecItemDelete(query as CFDictionary)
        var syncQuery = query
        syncQuery[kSecAttrSynchronizable as String] = true
        let s2 = SecItemDelete(syncQuery as CFDictionary)
        sandboxKeychainLogger.info(
            "delete sshSecret serverId=\(serverId.prefix(8)) legacyStatus=\(s1) syncStatus=\(s2)"
        )
    }
}
