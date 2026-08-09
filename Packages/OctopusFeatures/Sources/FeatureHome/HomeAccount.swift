import Foundation
import OctopusDomain

/// Ana sayfadaki hesap satırının hazır verisi.
///
/// Biçimlendirme görünümde değil burada: "359 gün" gibi metinler test
/// edilebilir bir yerde durmalı ve iki ekranda farklı yazılmamalı.
public struct HomeAccount: Equatable, Sendable {

    /// Aboneliğin aciliyeti — görünüm rengi buna bakar.
    public enum Urgency: Equatable, Sendable {
        /// Bolca vakit var; sessiz gri.
        case normal
        /// Bitmesine az kaldı; uyarı rengi.
        case soon
        /// Süresi dolmuş.
        case expired
    }

    /// Kaynağın adı — başlıkta kullanıcı adının yanında durur.
    public let sourceName: String
    public let username: String?
    /// Son senkronizasyon anı.
    ///
    /// ⚠️ Abonelik bilgisi olmayan kaynaklarda (M3U) ikinci bilgi kutusunu
    /// bu doldurur; tek başına kalan bir kutu ortada asılı duruyordu.
    public let lastSyncedAt: Date?
    public let expiresAt: Date?
    public let remainingDays: Int?
    public let urgency: Urgency

    /// ⚠️ Eşik neden 7 gün: IPTV aboneliklerinin çoğu aylık yenilenir.
    /// Bir hafta, kullanıcının bayisine ulaşıp yenilemesi için yeterli
    /// ama her gün uyarı görmesine yol açmayacak kadar dar.
    static let warningThresholdDays = 7

    public init(playlist: Playlist, now: Date) {
        self.sourceName = playlist.name
        self.username = Self.username(from: playlist.kind)
        self.lastSyncedAt = playlist.lastSyncedAt
        self.expiresAt = playlist.expiresAt
        self.remainingDays = playlist.remainingDays(from: now)

        switch remainingDays {
        case .none:
            urgency = .normal
        case .some(0):
            urgency = .expired
        case .some(let days) where days <= Self.warningThresholdDays:
            urgency = .soon
        default:
            urgency = .normal
        }
    }

    /// Yalnızca Xtream kaynaklarda kullanıcı adı vardır.
    private static func username(from kind: Playlist.Kind) -> String? {
        if case .xtream(_, let username) = kind { return username }
        return nil
    }

    /// Bitiş tarihi — "03.08.2027".
    ///
    /// Referansta tarih ve kalan gün birlikte gösteriliyor; başlık kartı
    /// buna yer açacak kadar geniş. Tarih "ne zaman biteceğini" söyler,
    /// kalan gün "acele etmeli miyim"i — ikisi farklı sorular.
    public var expiryDateText: String? {
        guard let expiresAt else { return nil }
        return Self.dateFormatter.string(from: expiresAt)
    }

    /// ⚠️ Formatter **bir kez** kuruluyor: `DateFormatter` üretimi pahalı
    /// ve bu değer her yeniden çizimde okunuyor.
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter
    }()

    /// "359 gün kaldı" / "Bugün bitiyor" / "Süresi doldu".
    public var expiryText: String? {
        guard let remainingDays else { return nil }

        switch remainingDays {
        case 0 where urgency == .expired: return "Aboneliğin süresi doldu"
        case 0: return "Bugün bitiyor"
        case 1: return "1 gün kaldı"
        default: return "\(remainingDays) gün kaldı"
        }
    }

    /// "2 saat önce" — son güncellemenin okunur hâli.
    public var lastSyncedText: String? {
        guard let lastSyncedAt else { return nil }
        return Self.relativeFormatter.localizedString(for: lastSyncedAt, relativeTo: Date())
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.unitsStyle = .full
        return formatter
    }()

    /// Gösterilecek bir şey var mı? Yoksa kutular hiç çizilmez.
    public var hasContent: Bool {
        username != nil || expiryText != nil || lastSyncedText != nil
    }
}
