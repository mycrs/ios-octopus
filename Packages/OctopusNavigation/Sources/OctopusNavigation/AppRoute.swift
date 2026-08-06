import Foundation
import OctopusDomain

/// Alt sekmeler.
public enum AppTab: String, CaseIterable, Hashable, Sendable, Identifiable {
    case home
    case live
    case movies
    case series
    case favorites

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .home: return "Ana Sayfa"
        case .live: return "Canlı TV"
        case .movies: return "Filmler"
        case .series: return "Diziler"
        case .favorites: return "Favoriler"
        }
    }

    public var icon: String {
        switch self {
        case .home: return "house.fill"
        case .live: return "tv.fill"
        case .movies: return "film.fill"
        case .series: return "rectangle.stack.fill"
        case .favorites: return "heart.fill"
        }
    }

    /// Açılışta gösterilebilecek sekmeler — artık `CaseIterable` ile aynı.
    ///
    /// Arama ve ayarlar hiç sekme değil (üst bar ikonu), o yüzden zaten
    /// burada olamazlar. Favoriler içerik gösteren bir ekran — Netflix'in
    /// "Listem"i gibi kullanıcı doğrudan oradan açılmak isteyebilir.
    public static let startupOptions: [AppTab] = allCases
}

/// Uygulama içi hedefler.
///
/// ⚠️ Route'lar **yalnızca kimlik taşır**, entity taşımaz.
/// Sebebi: deeplink, durum geri yükleme ve `Hashable` maliyeti.
/// Hedef ekran veriyi kendi repository'sinden tazeler.
public enum AppRoute: Hashable, Sendable {
    case channels(categoryID: MediaCategory.ID?)
    case movieDetail(Movie.ID)
    case seriesDetail(Series.ID)
    case seasonEpisodes(seriesID: Series.ID, seasonNumber: Int)
    case categoryList(kind: MediaCategory.Kind)
    /// Bir kanalın gün boyu yayın akışı.
    case channelGuide(Channel.ID)
    /// Birleşik arama — sekme değil, üst bar ikonuyla açılır.
    case search
    case playlistManager
    case about
}

/// Modal olarak sunulan ekranlar (stack'e girmez).
public enum AppSheet: Hashable, Identifiable, Sendable {
    case addPlaylist
    case editPlaylist(Playlist.ID)
    case trackSelection
    case parentalLock

    public var id: Self { self }
}

/// Tam ekran oynatıcı sunumu.
///
/// Akış URL'si taşınmaz — `FeaturePlayer` kendisi `StreamResolving` ile üretir.
/// Böylece süresi dolmuş bir URL ile ekran açılmaz.
public struct PlayerPresentation: Hashable, Identifiable, Sendable {
    public let source: PlaybackItem.Source
    public let startAt: TimeInterval?

    public var id: String { source.storageKey }

    public init(source: PlaybackItem.Source, startAt: TimeInterval? = nil) {
        self.source = source
        self.startAt = startAt
    }
}
