import Foundation
import OctopusDomain

/// Alt sekmeler.
public enum AppTab: String, CaseIterable, Hashable, Sendable, Identifiable {
    case home
    case live
    case movies
    case series
    case search
    case settings

    public var id: String { rawValue }
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
    case favorites
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
