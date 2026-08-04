import SwiftUI
import OctopusDomain

/// Hataların **sunumu**. Domain sadece hatanın ne olduğunu bilir;
/// nasıl gösterileceği burada tanımlanır.
///
/// Bu ayrım sayesinde metinleri değiştirmek veya yeni dil eklemek
/// iş mantığına hiç dokunmadan yapılır.
extension AppError {

    public var userTitle: String {
        switch self {
        case .network: return "Bağlantı yok"
        case .unauthorized: return "Giriş yapılamadı"
        case .connectionLimitReached: return "Bağlantı sınırı doldu"
        case .invalidResponse: return "İçerik okunamadı"
        case .storage: return "Kaydedilemedi"
        case .playbackFailed: return "Yayın açılamadı"
        case .notFound: return "Bulunamadı"
        case .unknown: return "Bir sorun oluştu"
        }
    }

    public var userMessage: String {
        switch self {
        case .network:
            return "İnternet bağlantını kontrol edip tekrar dene."
        case .unauthorized:
            return "Kullanıcı adı veya parola hatalı. Aboneliğinin süresi dolmuş olabilir."
        case .connectionLimitReached:
            return "Bu hesapla aynı anda izin verilen cihaz sayısına ulaşıldı. Başka bir cihazda açık olan yayını kapat."
        case .invalidResponse:
            return "Sunucudan gelen liste anlaşılamadı. Kaynak adresini kontrol et."
        case .storage:
            return "Veriler cihaza yazılamadı. Depolama alanın dolu olabilir."
        case .playbackFailed:
            return "Kanal geçici olarak yayında olmayabilir. Başka bir kanal dene."
        case .notFound:
            return "Aradığın içerik artık bu kaynakta yok."
        case .unknown:
            return "Beklenmeyen bir durumla karşılaşıldı."
        }
    }

    public var iconName: String {
        switch self {
        case .network: return "wifi.slash"
        case .unauthorized: return "person.crop.circle.badge.exclamationmark"
        case .connectionLimitReached: return "person.2.slash"
        case .invalidResponse: return "doc.text.magnifyingglass"
        case .storage: return "internaldrive"
        case .playbackFailed: return "play.slash"
        case .notFound: return "questionmark.folder"
        case .unknown: return "exclamationmark.triangle"
        }
    }

    /// Kullanıcıya sunulacak birincil eylemin etiketi.
    public var primaryActionTitle: String? {
        if requiresReauthentication { return "Kaynağı düzenle" }
        return isRetryable ? "Tekrar dene" : nil
    }
}
