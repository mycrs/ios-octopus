import OctopusDomain

extension SyncStage {
    var title: String {
        switch self {
        case .idle: return "Hazırlanıyor"
        case .authenticating: return "Hesap doğrulanıyor"
        case .fetchingCategories: return "Kategoriler alınıyor"
        case .fetchingChannels: return "Kanallar alınıyor"
        case .fetchingMovies: return "Filmler alınıyor"
        case .fetchingSeries: return "Diziler alınıyor"
        case .fetchingEPG: return "Yayın akışı alınıyor"
        case .persisting: return "Cihaza kaydediliyor"
        case .finished: return "Tamamlandı"
        case .failed: return "Bir sorun oluştu"
        }
    }

    var catalogKind: SyncCatalogKind? {
        switch self {
        case .fetchingChannels: return .channels
        case .fetchingMovies: return .movies
        case .fetchingSeries: return .series
        default: return nil
        }
    }

    /// Toplam bilinmediğinde bile alt ilerleme çizgisi aşamalar arasında
    /// geriye sıçramasın; dairesel gösterge bu sırada spinner olarak kalır.
    var fallbackFraction: Double {
        switch self {
        case .idle: return 0
        case .authenticating: return 0.05
        case .fetchingCategories: return 0.10
        case .fetchingChannels: return 0.15
        case .fetchingMovies: return 0.45
        case .fetchingSeries: return 0.70
        case .fetchingEPG: return 0.90
        case .persisting: return 0.95
        case .finished: return 1
        case .failed: return 0
        }
    }
}
