import Foundation
import Security

struct TokenStore: Sendable {
    private let service = "com.jaide.HermesTray.session-token"

    private func query(for account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private func fallbackKey(_ account: String) -> String { "\(service).\(account)" }

    func read(for account: String) -> String? {
        // A failed Keychain update must not hide the newer fallback token.
        if let fallback = UserDefaults.standard.string(forKey: fallbackKey(account)) { return fallback }
        var request = query(for: account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ token: String, for account: String) {
        let data = Data(token.utf8)
        let request = query(for: account)
        var status = SecItemUpdate(request as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insertion = request
            insertion[kSecValueData as String] = data
            status = SecItemAdd(insertion as CFDictionary, nil)
        }
        let defaults = UserDefaults.standard
        if status == errSecSuccess { defaults.removeObject(forKey: fallbackKey(account)) }
        else { defaults.set(token, forKey: fallbackKey(account)) }
    }
}
