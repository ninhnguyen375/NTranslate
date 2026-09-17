import Foundation
import Security

struct APIKeyStore: Sendable {
    static let shared = APIKeyStore(service: "local.ninh.ntranslate", account: "apiKey")
    /// Optional key for the speech endpoint. Empty means "use the LLM key", so a user pointing
    /// both services at one host never types the same key twice and no migration is needed.
    static let speech = APIKeyStore(service: "local.ninh.ntranslate", account: "speechAPIKey")

    let service: String
    let account: String

    /// Keys live in a 0600 file next to config.json. Reading Keychain from a self-signed build
    /// prompts for the password after every rebuild, because the item's partition list pins cdhash.
    var fileURL: URL {
        URL(fileURLWithPath: AppConfig.configPath).deletingLastPathComponent()
            .appendingPathComponent("\(account).key")
    }

    func load() throws -> String? {
        if let data = FileManager.default.contents(atPath: fileURL.path) {
            let value = String(decoding: data, as: UTF8.self)
            return value.isEmpty ? nil : value
        }
        // One-time migration from Keychain. The file is written even when empty, so Keychain
        // (and its password prompt) is never touched again once the file exists.
        let legacy = try loadFromKeychain()
        try writeFile(legacy ?? "")
        return legacy
    }

    func save(_ value: String) throws {
        try writeFile(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func delete() throws {
        try writeFile("")
    }

    private func writeFile(_ value: String) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(value.utf8).write(to: fileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private func loadFromKeychain() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw APIKeyStoreError.status(status) }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw APIKeyStoreError.invalidData
        }
        return value
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

enum APIKeyStoreError: LocalizedError {
    case status(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case let .status(status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown Keychain error"
            return "Keychain error \(status): \(message)"
        case .invalidData:
            return "API key in Keychain is not valid UTF-8."
        }
    }
}
