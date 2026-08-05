import Foundation
import CryptoKit
import OctopusCore
import OctopusDomain

/// Ebeveyn kilidi — PIN Keychain'de **tuzlu özet** olarak saklanır.
///
/// ⚠️ PIN asla düz metin yazılmaz. Referans projede önce düz metin
/// saklanıyordu ve sonradan tuzlu SHA-256'ya taşındı; buraya baştan
/// doğru biçimde yazıldı.
///
/// Tuz her PIN belirlemede yeniden üretilir: aynı PIN farklı cihazlarda
/// farklı özet üretir, hazır tablo saldırısı işe yaramaz.
public actor KeychainParentalControl: ParentalControlling {

    private let secrets: SecretStore
    private var unlockedInSession = false

    private static let hashKey = "parental.pin.hash"
    private static let saltKey = "parental.pin.salt"

    public init(secrets: SecretStore) {
        self.secrets = secrets
    }

    // MARK: - Durum

    public func isEnabled() async -> Bool {
        (try? secrets.read(for: Self.hashKey)) as? String != nil
    }

    public func isUnlocked() async -> Bool {
        unlockedInSession
    }

    // MARK: - Kurulum

    public func setPIN(_ pin: String) async throws {
        guard let normalized = Self.normalizePIN(pin) else {
            throw ParentalControlError.invalidFormat
        }

        let salt = Self.makeSalt()
        let hash = Self.hash(pin: normalized, salt: salt)

        do {
            try secrets.save(hash, for: Self.hashKey)
            try secrets.save(salt, for: Self.saltKey)
        } catch {
            Log.app.error("Ebeveyn PIN'i kaydedilemedi: \(String(describing: error))")
            throw ParentalControlError.storageFailure
        }

        // PIN'i belirleyen kişi zaten yetkili; tekrar sormaya gerek yok.
        unlockedInSession = true
    }

    @discardableResult
    public func unlock(with pin: String) async -> Bool {
        guard let normalized = Self.normalizePIN(pin),
              let storedHash = try? secrets.read(for: Self.hashKey),
              let salt = try? secrets.read(for: Self.saltKey),
              let storedHash, let salt
        else { return false }

        let candidate = Self.hash(pin: normalized, salt: salt)

        // Sabit süreli karşılaştırma: özet uzunlukları aynı olduğu için
        // erken çıkışlı `==` zamanlama bilgisi sızdırabilir.
        guard Self.constantTimeEquals(candidate, storedHash) else { return false }

        unlockedInSession = true
        return true
    }

    public func lock() async {
        unlockedInSession = false
    }

    public func disable(with pin: String) async throws {
        guard await isEnabled() else { throw ParentalControlError.notConfigured }
        guard await unlock(with: pin) else { throw ParentalControlError.wrongPIN }

        do {
            try secrets.delete(for: Self.hashKey)
            try secrets.delete(for: Self.saltKey)
        } catch {
            throw ParentalControlError.storageFailure
        }
        unlockedInSession = false
    }

    // MARK: - Kriptografi

    static func makeSalt() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        // Rastgelelik kaynağı başarısız olursa (pratikte olmaz) yine de
        // benzersiz bir değer üretilir.
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            bytes = Array(UUID().uuidString.utf8)
        }
        return Data(bytes).base64EncodedString()
    }

    static func hash(pin: String, salt: String) -> String {
        let input = Data((salt + pin).utf8)
        return SHA256.hash(data: input)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Uzunluk eşitse tüm baytları karşılaştırır, erken çıkmaz.
    static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }

        var difference: UInt8 = 0
        for index in left.indices {
            difference |= left[index] ^ right[index]
        }
        return difference == 0
    }
}
