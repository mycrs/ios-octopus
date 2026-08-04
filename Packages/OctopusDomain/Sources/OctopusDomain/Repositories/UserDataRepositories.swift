import Foundation

// Kullanıcıya ait veriler. Sağlayıcıdan bağımsızdır; kaynak silinse bile
// (kullanıcı isterse) korunabilir.

/// Favoriler.
public protocol FavoritesRepository: Sendable {
    func isFavorite(_ source: PlaybackItem.Source) async throws -> Bool
    func toggle(_ source: PlaybackItem.Source) async throws -> Bool
    func favoriteChannels(playlistID: Playlist.ID) async throws -> [Channel]
    func favoriteMovies(playlistID: Playlist.ID) async throws -> [Movie]
    func favoriteSeries(playlistID: Playlist.ID) async throws -> [Series]

    /// Kalp ikonunun anında güncellenmesi için.
    func observeFavoriteKeys() -> AsyncStream<Set<String>>
}

/// İzleme ilerlemesi — "kaldığın yerden devam et".
public protocol PlaybackProgressRepository: Sendable {
    func progress(for source: PlaybackItem.Source) async throws -> PlaybackProgress?

    /// Oynatma sırasında periyodik çağrılır (~5 sn'de bir).
    func save(
        _ progress: PlaybackProgress,
        for source: PlaybackItem.Source
    ) async throws

    /// Ana sayfadaki "İzlemeye devam et" rafı.
    /// Bitmiş (>%95) olanlar hariç tutulur.
    func continueWatching(
        playlistID: Playlist.ID,
        limit: Int
    ) async throws -> [PlaybackProgress]

    func clear(for source: PlaybackItem.Source) async throws
    func clearAll() async throws
}

/// Son izlenenler (canlı kanal geçmişi dahil).
public protocol WatchHistoryRepository: Sendable {
    func record(_ source: PlaybackItem.Source, at date: Date) async throws
    func recentChannels(playlistID: Playlist.ID, limit: Int) async throws -> [Channel]
    func clearAll() async throws
}
