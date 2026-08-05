import Foundation
import Combine
import OctopusDomain
import OctopusDesignSystem

/// Kullanıcının favorileri: kanal, film ve dizi bir arada.
@MainActor
public final class FavoritesViewModel: ObservableObject {

    @Published public private(set) var channels: [Channel] = []
    @Published public private(set) var movies: [Movie] = []
    @Published public private(set) var series: [Series] = []
    @Published public private(set) var state: LoadableState<Int> = .idle

    /// Hiç favori yoksa boş durum gösterilir.
    public var isEmpty: Bool {
        channels.isEmpty && movies.isEmpty && series.isEmpty
    }

    private let dependencies: FavoritesDependencies
    private var activePlaylistID: Playlist.ID?
    private var observationTask: Task<Void, Never>?

    public init(dependencies: FavoritesDependencies) {
        self.dependencies = dependencies
    }

    deinit {
        observationTask?.cancel()
    }

    public func load() async {
        if isEmpty { state = .loading }

        do {
            guard let playlist = try await dependencies.playlists.activePlaylist() else {
                state = .loaded(0)
                clear()
                return
            }
            activePlaylistID = playlist.id
            try await reload(playlistID: playlist.id)
            observeChanges()
        } catch {
            state = .failed(AppError.wrap(error))
        }
    }

    private func reload(playlistID: Playlist.ID) async throws {
        // Üç sorgu paralel: favori listeleri birbirinden bağımsız.
        async let channelList = dependencies.favorites.favoriteChannels(playlistID: playlistID)
        async let movieList = dependencies.favorites.favoriteMovies(playlistID: playlistID)
        async let seriesList = dependencies.favorites.favoriteSeries(playlistID: playlistID)

        channels = try await channelList
        movies = try await movieList
        series = try await seriesList
        state = .loaded(channels.count + movies.count + series.count)
    }

    /// Başka bir ekranda favori kaldırılırsa liste kendini tazeler.
    private func observeChanges() {
        observationTask?.cancel()
        observationTask = Task { [weak self, dependencies] in
            var isFirst = true
            for await _ in dependencies.favorites.observeFavoriteKeys() {
                // İlk yayın mevcut durumdur; az önce zaten okundu.
                if isFirst { isFirst = false; continue }

                guard let self, !Task.isCancelled,
                      let playlistID = self.activePlaylistID
                else { return }
                try? await self.reload(playlistID: playlistID)
            }
        }
    }

    public func removeChannel(_ channel: Channel) async {
        _ = try? await dependencies.favorites.toggle(.channel(channel.id))
        await refreshQuietly()
    }

    public func removeMovie(_ movie: Movie) async {
        _ = try? await dependencies.favorites.toggle(.movie(movie.id))
        await refreshQuietly()
    }

    public func removeSeries(_ item: Series) async {
        _ = try? await dependencies.favorites.toggle(.series(item.id))
        await refreshQuietly()
    }

    /// Yükleme göstergesi olmadan tazeler — silme sonrası ekran titremesin.
    private func refreshQuietly() async {
        guard let playlistID = activePlaylistID else { return }
        try? await reload(playlistID: playlistID)
    }

    private func clear() {
        channels = []
        movies = []
        series = []
    }
}
