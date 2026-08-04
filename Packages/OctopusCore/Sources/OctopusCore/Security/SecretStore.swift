import Foundation
import Security

/// Keychain işlemlerinin ham hatası.
/// Data katmanı bunu sınırında `AppError.storage`'a çevirir —
/// böylece Core, Domain'e bağımlı olmadan kalır.
public enum SecretStoreError: Error, Equatable, Sendable {
    case encodingFailed
    case keychain(status: OSStatus)
}

/// Hassas veri deposu (parola, Xtream şifresi, token).
///
/// ⚠️ Parolalar **asla** Domain entity'sinde veya SQLite'ta tutulmaz.
/// `Playlist` yalnızca bir anahtar taşır; gerçek parola buradan okunur.
public protocol SecretStore: Sendable {
    func save(_ secret: String, for key: String) throws
    func read(for key: String) throws -> String?
    func delete(for key: String) throws
}

/// iOS Keychain tabanlı varsayılan implementasyon.
public struct KeychainSecretStore: SecretStore {

    private let service: String

    public init(service: String = "com.octopus.iptv.credentials") {
        self.service = service
    }

    public func save(_ secret: String, for key: String) throws {
        guard let data = secret.data(using: .utf8) else {
            throw SecretStoreError.encodingFailed
        }

        // Varsa üzerine yaz: önce sil, sonra ekle.
        // SecItemUpdate'ten daha basit ve "kayıt yok" durumunu ayrıca ele almayı gerektirmez.
        try? delete(for: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            // Cihaz bir kez açıldıktan sonra erişilebilir:
            // arka planda EPG senkronizasyonu yapabilmek için gerekli.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecretStoreError.keychain(status: status)
        }
    }

    public func read(for key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw SecretStoreError.keychain(status: status)
        }

        return String(data: data, encoding: .utf8)
    }

    public func delete(for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.keychain(status: status)
        }
    }
}
