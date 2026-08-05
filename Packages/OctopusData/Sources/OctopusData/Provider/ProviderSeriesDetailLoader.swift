import Foundation
import OctopusCore
import OctopusDomain

/// Sezon/bölüm ağacını sağlayıcıdan getirir.
///
/// Depo (`GRDBSeriesRepository`) yerel veriden sorumludur; uzak veriye
/// uzanmak için bu tipi kullanır. Böylece depo `ContentProvider`'ı
/// tanımak zorunda kalmaz.
public struct ProviderSeriesDetailLoader: SeriesDetailLoading {

    private let playlists: PlaylistRepository
    private let providerFactory: ContentProviderFactory

    public init(playlists: PlaylistRepository, providerFactory: ContentProviderFactory) {
        self.playlists = playlists
        self.providerFactory = providerFactory
    }

    public func loadDetails(
        for series: Series
    ) async throws -> (seasons: [Season], episodes: [Episode]) {
        guard let playlist = try await playlists.playlist(id: series.playlistID) else {
            // Kaynak silinmiş ama ekran hâlâ açık olabilir.
            throw AppError.notFound
        }

        let provider = try await providerFactory.makeProvider(for: playlist)
        let result = try await provider.fetchSeriesDetails(streamKey: series.streamKey)

        Log.sync.debug("Dizi ağacı alındı: \(result.episodes.count) bölüm")
        return result
    }
}

/// Film künyesini sağlayıcıdan getirir.
public struct ProviderMovieDetailLoader: MovieDetailLoading {

    private let playlists: PlaylistRepository
    private let providerFactory: ContentProviderFactory

    public init(playlists: PlaylistRepository, providerFactory: ContentProviderFactory) {
        self.playlists = playlists
        self.providerFactory = providerFactory
    }

    public func loadDetails(for movie: Movie) async throws -> Movie {
        guard let playlist = try await playlists.playlist(id: movie.playlistID) else {
            throw AppError.notFound
        }

        let provider = try await providerFactory.makeProvider(for: playlist)
        let fetched = try await provider.fetchMovieDetails(streamKey: movie.streamKey)

        // Detay ucu adı boş döndürebiliyor; liste verisindeki ad korunur.
        var result = fetched
        if result.title.isEmpty { result.title = movie.title }
        if result.categoryID == nil { result.categoryID = movie.categoryID }
        if result.posterURL == nil { result.posterURL = movie.posterURL }
        return result
    }
}
