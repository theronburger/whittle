import Foundation
import Security
import WhittleCore

enum PairingVault {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Bundle.main.bundleIdentifier ?? "Whittle",
         kSecAttrAccount as String: "paired-device"]
    }

    static func load() throws -> PairingTicket? {
        var request = query
        request[kSecReturnData as String] = true
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw vaultError(status) }
        let ticket = try JSONDecoder().decode(PairingTicket.self, from: data)
        try ticket.validate()
        return ticket
    }

    static func save(_ ticket: PairingTicket) throws {
        try ticket.validate()
        let data = try JSONEncoder().encode(ticket)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw vaultError(added) }
        } else if status != errSecSuccess { throw vaultError(status) }
    }

    static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw vaultError(status) }
    }

    private static func vaultError(_ status: OSStatus) -> NSError {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Couldn’t store the pairing securely. \(SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error")"])
    }
}
