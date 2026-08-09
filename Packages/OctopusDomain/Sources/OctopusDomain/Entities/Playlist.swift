import Foundation

/// Kullanıcının eklediği içerik kaynağı.
///
/// ⚠️ Parola **burada tutulmaz.** Yalnızca `credentialKey` taşınır;
/// gerçek parola `SecretStore` (Keychain) üzerinden okunur.
public struct Playlist: Identifiable, Hashable, Codable, Sendable {

    public typealias ID = Identifier<Playlist>

    /// Kaynağın türü. Yeni bir tür eklemek = burada bir case + yeni bir
    /// `ContentProvider` implementasyonu. Başka hiçbir yer değişmez.
    public enum Kind: Hashable, Codable, Sendable {
        /// Xtream Codes paneli. `player_api.php` üzerinden zengin metadata.
        case xtream(host: URL, username: String)
        /// Uzak M3U/M3U8 playlist adresi.
        case m3u(url: URL)
        /// Cihaza aktarılmış yerel M3U dosyası.
        case m3uLocalFile(fileName: String)
        /// Bayi tarafından verilen aktivasyon kodu.
        /// Panel kodu çözüp gerçek Xtream bilgilerini döndürür.
        case activationCode(code: String)
    }

    public let id: ID
    public var name: String
    public var kind: Kind

    /// Harici XMLTV EPG adresi. Xtream'de genellikle `nil` (EPG API'den gelir).
    public var epgURL: URL?

    /// Keychain'deki parola kaydının anahtarı.
    public var credentialKey: String { "playlist.\(id.value)" }

    public var createdAt: Date
    public var lastSyncedAt: Date?

    /// Uygulamanın şu an gösterdiği kaynak mı?
    public var isActive: Bool

    /// Aboneliğin bitiş tarihi — her senkronizasyonda panelden tazelenir.
    ///
    /// ⚠️ Bilgi `authenticate()` çağrısında zaten geliyordu ama atılıyordu.
    /// Kullanıcı için en değerli tek veri bu: "kaç günüm kaldı". M3U
    /// kaynaklarda böyle bir kavram yok, `nil` kalır.
    public var expiresAt: Date?

    public init(
        id: ID,
        name: String,
        kind: Kind,
        epgURL: URL? = nil,
        createdAt: Date,
        lastSyncedAt: Date? = nil,
        isActive: Bool = false,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.epgURL = epgURL
        self.createdAt = createdAt
        self.lastSyncedAt = lastSyncedAt
        self.isActive = isActive
        self.expiresAt = expiresAt
    }

    /// Abonelik bitişine kalan tam gün sayısı. Süresi dolmuşsa `0`.
    public func remainingDays(from date: Date) -> Int? {
        guard let expiresAt else { return nil }
        let seconds = expiresAt.timeIntervalSince(date)
        guard seconds > 0 else { return 0 }
        return Int(seconds / 86_400)
    }
}

extension Playlist.Kind {
    /// Bu kaynak Xtream mi? (VOD/Dizi desteği yalnızca Xtream'de garanti.)
    public var isXtream: Bool {
        if case .xtream = self { return true }
        return false
    }
}

/// Kaynağa bağlanıldığında dönen hesap bilgisi (abonelik durumu).
public struct ProviderAccount: Hashable, Codable, Sendable {
    public let username: String
    public let expiresAt: Date?
    public let isTrial: Bool
    public let maxConnections: Int
    public let activeConnections: Int

    public init(
        username: String,
        expiresAt: Date?,
        isTrial: Bool,
        maxConnections: Int,
        activeConnections: Int
    ) {
        self.username = username
        self.expiresAt = expiresAt
        self.isTrial = isTrial
        self.maxConnections = maxConnections
        self.activeConnections = activeConnections
    }

    public func isExpired(at date: Date) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt < date
    }
}
