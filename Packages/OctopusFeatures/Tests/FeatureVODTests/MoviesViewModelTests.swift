import XCTest
import OctopusDomain
@testable import FeatureVOD

/// Film kataloğu: sayfalama, arama, favoriler.
@MainActor
final class MoviesViewModelTests: XCTestCase {

    private var playlists: StubPlaylists!
    private var vod: StubVOD!
    private var favorites: StubFavorites!

    override func setUp() async throws {
        playlists = StubPlaylists()
        vod = StubVOD()
        favorites = StubFavorites()
    }

    private func makeViewModel(pageSize: Int = 5) -> MoviesViewModel {
        MoviesViewModel(
            dependencies: VODDependencies(
                playlists: playlists,
                vod: vod,
                favorites: favorites,
                progress: NoopProgress()
            ),
            pageSize: pageSize,
            searchDebounce: .milliseconds(10)
        )
    }

    private func waitABit(_ ms: UInt64 = 100) async {
        try? await Task.sleep(nanoseconds: ms * 1_000_000)
    }

    private func makeMovies(_ count: Int, prefix: String = "Film") -> [Movie] {
        (0..<count).map {
            Movie(
                id: Movie.ID("\(prefix)-\($0)"),
                playlistID: "p1",
                title: "\(prefix) \($0)",
                streamKey: "\($0)"
            )
        }
    }

    // MARK: - Sayfalama
    //
    // Referans projede tüm katalog tek seferde belleğe alınıyordu ve
    // 20.000 filmlik hesapta uygulama düşüyordu.

    func test_loadsFirstPageOnly() async {
        vod.stored = makeMovies(50)

        let viewModel = makeViewModel(pageSize: 5)
        await viewModel.load()

        XCTAssertEqual(viewModel.movies.count, 5, "Yalnızca ilk sayfa yüklenmeli")
        XCTAssertTrue(viewModel.canLoadMore)
    }

    func test_loadMoreAppendsNextPage() async {
        vod.stored = makeMovies(12)

        let viewModel = makeViewModel(pageSize: 5)
        await viewModel.load()
        await viewModel.loadMore()

        XCTAssertEqual(viewModel.movies.count, 10)
        XCTAssertEqual(viewModel.movies.map(\.title).prefix(2), ["Film 0", "Film 1"])
    }

    func test_lastPageStopsPagination() async {
        vod.stored = makeMovies(7)

        let viewModel = makeViewModel(pageSize: 5)
        await viewModel.load()
        await viewModel.loadMore()

        XCTAssertEqual(viewModel.movies.count, 7)
        XCTAssertFalse(viewModel.canLoadMore, "Eksik sayfa geldiyse liste bitmiştir")

        // Fazladan çağrı zarar vermemeli.
        await viewModel.loadMore()
        XCTAssertEqual(viewModel.movies.count, 7)
    }

    func test_pageErrorKeepsExistingList() async {
        vod.stored = makeMovies(20)

        let viewModel = makeViewModel(pageSize: 5)
        await viewModel.load()
        XCTAssertEqual(viewModel.movies.count, 5)

        vod.error = AppError.network(reason: "kopuk")
        await viewModel.loadMore()

        XCTAssertEqual(viewModel.movies.count, 5, "Sayfa hatası mevcut listeyi düşürmemeli")
        XCTAssertFalse(viewModel.canLoadMore)
    }

    func test_loadMoreIfNeededOnlyTriggersNearEnd() async {
        vod.stored = makeMovies(50)

        let viewModel = makeViewModel(pageSize: 20)
        await viewModel.load()
        let initialRequests = vod.pageRequests.count

        // Baştaki öğe: tetiklememeli.
        await viewModel.loadMoreIfNeeded(currentItem: viewModel.movies[0])
        XCTAssertEqual(vod.pageRequests.count, initialRequests)

        // Sona yakın öğe: tetiklemeli.
        await viewModel.loadMoreIfNeeded(currentItem: viewModel.movies[18])
        XCTAssertGreaterThan(vod.pageRequests.count, initialRequests)
    }

    // MARK: - Kategori

    func test_categoryChangeResetsPagination() async {
        vod.stored = makeMovies(20)

        let viewModel = makeViewModel(pageSize: 5)
        await viewModel.load()
        await viewModel.loadMore()
        XCTAssertEqual(viewModel.movies.count, 10)

        await viewModel.selectCategory(MediaCategory.ID("aksiyon"))

        XCTAssertEqual(viewModel.movies.count, 5, "Kategori değişince baştan yüklenmeli")
        XCTAssertEqual(vod.pageRequests.last?.offset, 0)
        XCTAssertEqual(vod.pageRequests.last?.categoryID?.value, "aksiyon")
    }

    // MARK: - Arama

    func test_searchReplacesListAndStopsPagination() async {
        vod.stored = makeMovies(20)
        vod.searchResults = makeMovies(3, prefix: "Sonuç")

        let viewModel = makeViewModel(pageSize: 5)
        await viewModel.load()

        viewModel.searchText = "sonuç"
        await waitABit()

        XCTAssertEqual(viewModel.movies.count, 3)
        XCTAssertFalse(viewModel.canLoadMore, "Arama sonuçlarında sayfalama olmamalı")

        // Arama sırasında loadMore çağrılsa bile liste bozulmamalı.
        await viewModel.loadMore()
        XCTAssertEqual(viewModel.movies.count, 3)
    }

    func test_clearingSearchRestoresCatalog() async {
        vod.stored = makeMovies(20)
        vod.searchResults = makeMovies(3, prefix: "Sonuç")

        let viewModel = makeViewModel(pageSize: 5)
        await viewModel.load()

        viewModel.searchText = "sonuç"
        await waitABit()
        viewModel.searchText = ""
        await waitABit()

        XCTAssertFalse(viewModel.isSearching)
        XCTAssertEqual(viewModel.movies.count, 5)
        XCTAssertTrue(viewModel.canLoadMore)
    }

    // MARK: - Kaynak yok

    func test_noActivePlaylistShowsEmptyNotError() async {
        playlists.active = nil

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertTrue(viewModel.movies.isEmpty)
        XCTAssertEqual(viewModel.state, .loaded(0))
    }

    // MARK: - Favoriler

    func test_toggleFavorite() async {
        vod.stored = makeMovies(3)

        let viewModel = makeViewModel()
        await viewModel.load()
        await waitABit()

        let movie = viewModel.movies[0]
        XCTAssertFalse(viewModel.isFavorite(movie))

        await viewModel.toggleFavorite(movie)
        await waitABit()

        XCTAssertTrue(viewModel.isFavorite(movie))
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

private final class StubVOD: VODRepository, @unchecked Sendable {

    var stored: [Movie] = []
    var searchResults: [Movie] = []
    var error: Error?

    private(set) var pageRequests: [(categoryID: MediaCategory.ID?, offset: Int)] = []

    func categories(playlistID: Playlist.ID) async throws -> [MediaCategory] { [] }

    func movies(
        playlistID: Playlist.ID,
        categoryID: MediaCategory.ID?,
        limit: Int,
        offset: Int
    ) async throws -> [Movie] {
        pageRequests.append((categoryID, offset))
        if let error { throw error }
        return Array(stored.dropFirst(offset).prefix(limit))
    }

    func movie(id: Movie.ID) async throws -> Movie? { stored.first { $0.id == id } }
    func loadDetails(id: Movie.ID) async throws -> Movie { throw AppError.notFound }

    func search(query: String, playlistID: Playlist.ID, limit: Int) async throws -> [Movie] {
        searchResults
    }

    func recentlyAdded(playlistID: Playlist.ID, limit: Int) async throws -> [Movie] { [] }
}

private final class StubFavorites: FavoritesRepository, @unchecked Sendable {

    private var keys: Set<String> = []
    private var continuation: AsyncStream<Set<String>>.Continuation?

    func isFavorite(_ source: PlaybackItem.Source) async throws -> Bool {
        keys.contains(source.storageKey)
    }

    func toggle(_ source: PlaybackItem.Source) async throws -> Bool {
        let key = source.storageKey
        let added: Bool
        if keys.contains(key) { keys.remove(key); added = false }
        else { keys.insert(key); added = true }
        continuation?.yield(keys)
        return added
    }

    func favoriteChannels(playlistID: Playlist.ID) async throws -> [Channel] { [] }
    func favoriteMovies(playlistID: Playlist.ID) async throws -> [Movie] { [] }
    func favoriteSeries(playlistID: Playlist.ID) async throws -> [Series] { [] }

    func observeFavoriteKeys() -> AsyncStream<Set<String>> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(keys)
        }
    }
}

private struct NoopProgress: PlaybackProgressRepository {
    func progress(for source: PlaybackItem.Source) async throws -> PlaybackProgress? { nil }
    func save(_ progress: PlaybackProgress, for source: PlaybackItem.Source) async throws {}
    func continueWatching(playlistID: Playlist.ID, limit: Int) async throws -> [PlaybackProgress] { [] }
    func clear(for source: PlaybackItem.Source) async throws {}
    func clearAll() async throws {}
}
