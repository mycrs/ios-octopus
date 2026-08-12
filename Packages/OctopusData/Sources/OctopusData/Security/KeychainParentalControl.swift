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
    private let preferences: UserDefaults
    private var unlockedInSession = false

    private static let hashKey = "parental.pin.hash"
    private static let saltKey = "parental.pin.salt"
    private static let hiddenCategoriesKey = "parental.hiddenCategories"
    private static let defaultPIN = "0000"

    public init(secrets: SecretStore, preferences: UserDefaults = .standard) {
        self.secrets = secrets
        self.preferences = preferences
    }

    // MARK: - Durum

    public func isEnabled() async -> Bool {
        // +18 koruması ilk kurulumdan itibaren açıktır; kullanıcı PIN
        // oluşturmadan önce güvenli varsayılan 0000 geçerlidir.
        true
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

    public func changePIN(currentPIN: String, newPIN: String) async throws {
        guard Self.normalizePIN(newPIN) != nil else {
            throw ParentalControlError.invalidFormat
        }
        guard await unlock(with: currentPIN) else {
            throw ParentalControlError.wrongPIN
        }
        try await setPIN(newPIN)
    }

    @discardableResult
    public func unlock(with pin: String) async -> Bool {
        guard let normalized = Self.normalizePIN(pin) else { return false }

        guard let storedHash = try? secrets.read(for: Self.hashKey),
              let salt = try? secrets.read(for: Self.saltKey)
        else {
            // Özelleştirilmiş PIN yoksa cihazın güvenli başlangıç PIN'i.
            guard Self.constantTimeEquals(normalized, Self.defaultPIN) else { return false }
            unlockedInSession = true
            return true
        }

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
        guard await unlock(with: pin) else { throw ParentalControlError.wrongPIN }

        do {
            try secrets.delete(for: Self.hashKey)
            try secrets.delete(for: Self.saltKey)
        } catch {
            throw ParentalControlError.storageFailure
        }
        // Koruma kapatılmaz; özel PIN kaldırılınca varsayılan 0000'a döner.
        unlockedInSession = false
    }

    // MARK: - Kategori görünürlüğü

    public func hiddenCategoryKeys() async -> Set<String> {
        Set(preferences.stringArray(forKey: Self.hiddenCategoriesKey) ?? [])
    }

    public func setCategory(_ category: MediaCategory, hidden: Bool) async {
        var keys = await hiddenCategoryKeys()
        let key = ParentalFilter.categoryKey(category)
        if hidden {
            keys.insert(key)
        } else {
            keys.remove(key)
        }
        preferences.set(keys.sorted(), forKey: Self.hiddenCategoriesKey)
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
