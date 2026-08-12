import Foundation

/// Aktivasyon kodunun çözülmesiyle elde edilen hesap bilgileri.
///
/// Bayi müşteriye sunucu adresi ve parola yerine kısa bir kod verir;
/// kod panelde gerçek erişim bilgilerine çevrilir. Kullanıcı hiçbir zaman
/// sunucu adresi veya parola görmez.
public struct ActivationResult: Equatable, Sendable {

    /// Kodun arkasındaki gerçek kaynak — Xtream veya M3U.
    public let kind: Playlist.Kind
    /// Xtream kaynaklarında Keychain'e yazılacak parola.
    public let password: String?
    /// Kaynağa verilecek ad.
    public let displayName: String
    /// Bayinin müşteri kaydındaki ad — karşılama ekranında gösterilebilir.
    public let customerName: String?
    /// Kodla birlikte gelen bayi markası (varsa panel yapılandırmasını ezer).
    public let branding: BrandConfiguration?
    /// Liste ebeveyn kilidiyle korunuyor mu?
    public let isProtected: Bool
    /// Hızlı kurulumda belirlenen dört haneli liste erişim PIN'i.
    public let playlistPIN: String?

    public init(
        kind: Playlist.Kind,
        password: String?,
        displayName: String,
        customerName: String? = nil,
        branding: BrandConfiguration? = nil,
        isProtected: Bool = false,
        playlistPIN: String? = nil
    ) {
        self.kind = kind
        self.password = password
        self.displayName = displayName
        self.customerName = customerName
        self.branding = branding
        self.isProtected = isProtected
        self.playlistPIN = playlistPIN
    }
}

/// Aktivasyon kodu hataları.
///
/// `AppError`'dan ayrı: her durum kullanıcıya **farklı** bir eylem
/// öneriyor ("kodu kontrol et" ile "bayine başvur" aynı şey değil).
public enum ActivationError: Error, Equatable, Sendable {

    /// Kod yok veya devre dışı.
    case notFound
    /// Kodun süresi dolmuş.
    case expired
    /// Kod başka bir cihazda kullanılmış.
    case alreadyUsed
    /// Çok fazla hatalı deneme — geçici kilit.
    case tooManyAttempts
    /// Sunucu istek sınırı uyguluyor.
    case rateLimited
    /// Kod biçimi geçersiz (ağa çıkmadan da yakalanabilir).
    case invalidFormat
    /// Sunucu tanınmayan bir hata döndürdü.
    case unknown(String)

    /// Kullanıcı aynı kodu tekrar denemeli mi?
    public var isWorthRetrying: Bool {
        switch self {
        case .rateLimited, .tooManyAttempts, .unknown:
            return true
        case .notFound, .expired, .alreadyUsed, .invalidFormat:
            return false
        }
    }

    /// Kullanıcı bayisine başvurmalı mı?
    public var requiresResellerContact: Bool {
        switch self {
        case .expired, .alreadyUsed, .notFound:
            return true
        case .invalidFormat, .rateLimited, .tooManyAttempts, .unknown:
            return false
        }
    }

    /// Panelin döndürdüğü hata anahtarını eşler.
    public static func fromServerCode(_ raw: String) -> ActivationError {
        switch raw.lowercased() {
        case "code_not_found", "code_inactive":
            return .notFound
        case "code_expired":
            return .expired
        case "code_already_used":
            return .alreadyUsed
        case "too_many_attempts":
            return .tooManyAttempts
        case "rate_limited_redeem", "rate_limited_create", "rate_limited":
            return .rateLimited
        case "invalid_code_format":
            return .invalidFormat
        default:
            return .unknown(raw)
        }
    }
}

/// Aktivasyon kodunu çözer.
public protocol ActivationRedeeming: Sendable {
    func redeem(code: String) async throws -> ActivationResult
}

extension ActivationRedeeming {
    /// Kodu ağa gönderilecek hâle getirir.
    ///
    /// ⚠️ Kod **büyük harfe çevrilmiyor**. Önceden çevriliyordu ve bu,
    /// panel kodları büyük/küçük harfe duyarlıysa kullanıcının doğru
    /// yazdığı kodu sessizce bozuyordu — hiç test edilemeyen bir
    /// başarısızlık sınıfı. Kodun doğruluğuna karar verecek olan paneldir;
    /// uygulama yalnızca kullanıcının gözle görmediği şeyi (baş/son
    /// boşluk, aradaki boşluklar) temizler.
    ///
    /// ⚠️ Karakter süzgeci de kaldırıldı: hangi karakterlerin geçerli
    /// olduğunu panel belirliyor. Yerel bir "geçersiz karakter" kuralı,
    /// panelin ürettiği ama bizim beklemediğimiz bir kodu ağa hiç
    /// çıkmadan reddederdi. Burada yalnızca **boş girdi** elenir.
    public static func normalizeCode(_ raw: String) -> String? {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")

        // Tek karakterlik girdi kazara dokunuştur; ağa çıkmaya değmez.
        guard cleaned.count >= 2 else { return nil }
        return cleaned
    }
}
