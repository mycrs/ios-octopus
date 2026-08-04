import Foundation

/// Uygulama genelinde ortak hata dili.
///
/// Her katman kendi teknik hatasını (`URLError`, SQLite hatası, parse hatası…)
/// **kendi sınırında** bu tipe çevirir. UI katmanı ham teknik hata görmez.
///
/// ⚠️ Kullanıcıya gösterilecek metin burada **yok** — o sunum katmanının işi.
/// Bkz. `OctopusDesignSystem/AppError+Presentation.swift`
public enum AppError: Error, Equatable, Sendable {

    /// Ağ erişilemiyor, zaman aşımı, DNS hatası.
    case network(reason: String)

    /// Kaynak kimlik doğrulamayı reddetti (yanlış parola, süresi dolmuş abonelik).
    case unauthorized

    /// Aynı anda izin verilen bağlantı sayısı aşıldı — IPTV'de çok sık görülür.
    case connectionLimitReached

    /// Sunucu cevap verdi ama içerik anlaşılamadı (bozuk M3U, beklenmeyen JSON).
    case invalidResponse(reason: String)

    /// Yerel veritabanı hatası.
    case storage(reason: String)

    /// Oynatma motoru içeriği açamadı.
    case playbackFailed(reason: String)

    /// İstenen kayıt yok.
    case notFound

    /// Sınıflandırılamayan hata.
    case unknown(reason: String)

    /// Kullanıcıya "Tekrar dene" sunulmalı mı? — Bu bir **iş kuralıdır**, sunum değil.
    public var isRetryable: Bool {
        switch self {
        case .network, .invalidResponse, .playbackFailed, .connectionLimitReached, .unknown:
            return true
        case .unauthorized, .storage, .notFound:
            return false
        }
    }

    /// Kullanıcının kaynağı yeniden yapılandırması gerekiyor mu?
    public var requiresReauthentication: Bool {
        self == .unauthorized
    }
}

extension AppError {
    /// Herhangi bir `Error`'ı güvenle `AppError`'a çevirir.
    /// Katman sınırlarında `catch { throw AppError.wrap($0) }` şeklinde kullan.
    public static func wrap(_ error: Error) -> AppError {
        if let appError = error as? AppError { return appError }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .userAuthenticationRequired:
                return .unauthorized
            case .cancelled:
                return .unknown(reason: "İşlem iptal edildi")
            default:
                return .network(reason: urlError.localizedDescription)
            }
        }

        if error is DecodingError {
            return .invalidResponse(reason: String(describing: error))
        }

        return .unknown(reason: error.localizedDescription)
    }
}
