import XCTest
import OctopusDomain
@testable import FeatureFavorites

/// Favoriler ekranı: üç tür bir arada, canlı güncelleme, çıkarma.
@MainActor
final class FavoritesViewModelTests: XCTestCase {

    private var playlists: StubPlaylists!
    private var favorites: StubFavorites!

    override func setUp() async throws {
        playlists = StubPlaylists()
        favorites = StubFavorites()
    }

    private func makeViewModel() -> FavoritesViewModel {
        FavoritesViewModel(
            dependencies: FavoritesDependencies(
                playlists: playlists,
                favorites: favorites
            )
        )
    }

    /// Koşul gerçekleşene kadar kısa aralıklarla yoklar.
    ///
    /// ⚠️ Sabit `sleep` ile beklemek CI'da rastgele kırmızıya yol açıyordu:
    /// koşucu yüklüyken gözlem görevi verilen süre içinde sıraya girmiyor.
    /// Bekleme süresi değil **koşul** ölçülür.
    private func waitUntil(
        _ description: String,
        timeoutMS: UInt64 = 3_000,
        _ condition: () -> Bool
    ) async {
        let step: UInt64 = 10
        var waited: UInt64 = 0

        while waited < timeoutMS {
            if condition() { return }
            try? await Task.sleep(nanoseconds: step * 1_000_000)
            waited += step
        }
        XCTFail("Zaman aşımı: \(description)")
    }

    // MARK: - Yükleme

    func test_loadsAllThreeKinds() async {
        favorites.channels = [
            Channel(id: "c1", playlistID: "p1", name: "TRT 1", streamKey: "1")
        ]
        favorites.movies = [
            Movie(id: "m1", playlistID: "p1", title: "Film", streamKey: "1")
        ]
        favorites.series = [
            Series(id: "s1", playlistID: "p1", title: "Dizi", streamKey: "1")
        ]

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertEqual(viewModel.channels.count, 1)
        XCTAssertEqual(viewModel.movies.count, 1)
        XCTAssertEqual(viewModel.series.count, 1)
        XCTAssertFalse(viewModel.isEmpty)
        XCTAssertEqual(viewModel.state, .loaded(3))
    }

    func test_noFavoritesShowsEmptyNotError() async {
        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertTrue(viewModel.isEmpty)
        XCTAssertEqual(viewModel.state, .loaded(0))
    }

    func test_noActivePlaylistShowsEmpty() async {
        playlists.active = nil
        favorites.channels = [
            Channel(id: "c1", playlistID: "p1", name: "TRT 1", streamKey: "1")
        ]

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertTrue(viewModel.isEmpty, "Kaynak yokken favori listelenmemeli")
        XCTAssertEqual(viewModel.state, .loaded(0))
    }

    // MARK: - Çıkarma

    func test_removingChannelUpdatesList() async {
        favorites.channels = [
            Channel(id: "c1", playlistID: "p1", name: "TRT 1", streamKey: "1"),
            Channel(id: "c2", playlistID: "p1", name: "Show", streamKey: "2")
        ]

        let viewModel = makeViewModel()
        await viewModel.load()
        XCTAssertEqual(viewModel.channels.count, 2)

        await viewModel.removeChannel(viewModel.channels[0])

        XCTAssertEqual(viewModel.channels.count, 1)
        XCTAssertEqual(favorites.lastToggledKey, "live:c1")
    }

    func test_removingMovieUsesMovieKeyspace() async {
        favorites.movies = [
            Movie(id: "m1", playlistID: "p1", title: "Film", streamKey: "1")
        ]

        let viewModel = makeViewModel()
        await viewModel.load()
        await viewModel.removeMovie(viewModel.movies[0])

        XCTAssertEqual(favorites.lastToggledKey, "movie:m1")
    }

    func test_removingSeriesUsesSeriesKeyspace() async {
        favorites.series = [
            Series(id: "s1", playlistID: "p1", title: "Dizi", streamKey: "1")
        ]

        let viewModel = makeViewModel()
        await viewModel.load()
        await viewModel.removeSeries(viewModel.series[0])

        XCTAssertEqual(favorites.lastToggledKey, "series:s1")
    }

    // MARK: - Canlı güncelleme

    func test_externalChangeRefreshesList() async {
        // Kullanıcı başka bir ekranda favori eklerse burası da tazelenmeli.
        favorites.channels = [
            Channel(id: "c1", playlistID: "p1", name: "TRT 1", streamKey: "1")
        ]

        let viewModel = makeViewModel()
        await viewModel.load()
        await waitUntil("ilk liste yüklenmeli") { viewModel.channels.count == 1 }

        // ⚠️ Abone olunmadan yayın yapmak **kaybolur**: `AsyncStream`'in
        // continuation'ı gözlem görevi başlayana kadar yok. Eski hâlinde
        // buradaki 120 ms'lik uyku bunu şans eseri örtüyordu — süre değil,
        // aboneliğin kendisi beklenmeli.
        await waitUntil("gözlem başlamalı") { favorites.isObserving }

        favorites.channels.append(
            Channel(id: "c2", playlistID: "p1", name: "Yeni", streamKey: "2")
        )
        favorites.emitChange()

        await waitUntil("dış değişiklik listeye yansımalı") {
            viewModel.channels.count == 2
        }
    }
}

// MARK: - Sahteler

private final class StubPlaylists: PlaylistRepository, @unchecked Sendable {
    var active: Playlist? = Playlist(
        id: "p1",
        name: "Kaynak",
        kind: .m3u(url: URL(string: "http://example.com/p.m3u")!),
        createdAt: Date(timeIntervalSince1970: 0),
        isActive: true
    )

    func all() async throws -> [Playlist] { active.map { [$0] } ?? [] }
    func playlist(id: Playlist.ID) async throws -> Playlist? { active }
    func activePlaylist() async throws -> Playlist? { active }
    func add(_ playlist: Playlist, password: String?) async throws {}
    func update(_ playlist: Playlist) async throws {}
    func setActive(id: Playlist.ID) async throws {}
    func delete(id: Playlist.ID) async throws {}
}

private final class StubFavorites: FavoritesRepository, @unchecked Sendable {

    var channels: [Channel] = []
    var movies: [Movie] = []
    var series: [Series] = []

    private(set) var lastToggledKey: String?
    private var continuation: AsyncStream<Set<String>>.Continuation?

    func isFavorite(_ target: FavoriteTarget) async throws -> Bool { true }

    func toggle(_ target: FavoriteTarget) async throws -> Bool {
        lastToggledKey = target.storageKey

        // Çıkarma işlemini yansıt.
        switch target {
        case .channel(let id): channels.removeAll { $0.id == id }
        case .movie(let id): movies.removeAll { $0.id == id }
        case .series(let id): series.removeAll { $0.id == id }
        }
        return false
    }

    func favoriteChannels(playlistID: Playlist.ID) async throws -> [Channel] { channels }
    func favoriteMovies(playlistID: Playlist.ID) async throws -> [Movie] { movies }
    func favoriteSeries(playlistID: Playlist.ID) async throws -> [Series] { series }

    /// Abone olundu mu? Test, yayın yapmadan önce bunu bekler.
    private(set) var isObserving = false

    func observeFavoriteKeys() -> AsyncStream<Set<String>> {
        AsyncStream { continuation in
            self.continuation = continuation
            self.isObserving = true
            continuation.yield([])   // mevcut durum
        }
    }

    /// Başka bir ekranda favori değişmiş gibi davranır.
    func emitChange() {
        continuation?.yield(["değişti"])
    }
}
