import XCTest
import OctopusDomain
@testable import FeatureSeries

/// Dizi kataloğu. Sayfalama kalıbı film ekranıyla aynı olduğu için burada
/// yalnızca diziye özgü davranışlar ve temel akış doğrulanır.
@MainActor
final class SeriesViewModelTests: XCTestCase {

    private var playlists: StubPlaylists!
    private var series: StubSeries!
    private var favorites: StubFavorites!

    override func setUp() async throws {
        playlists = StubPlaylists()
        series = StubSeries()
        favorites = StubFavorites()
    }

    private func makeViewModel(pageSize: Int = 5) -> SeriesViewModel {
        SeriesViewModel(
            dependencies: SeriesDependencies(
                playlists: playlists,
                series: series,
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

    /// Koşul gerçekleşene kadar kısa aralıklarla yoklar.
    ///
    /// ⚠️ Sabit `sleep` ile beklemek CI'da rastgele kırmızıya yol açıyordu:
    /// koşucu paralel iş yüzünden yüklüyken 10 ms'lik geciktirme görevi
    /// 100 ms içinde sıraya girmiyor. Bekleme süresi değil **koşul** ölçülür.
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

    private func makeSeries(_ count: Int) -> [Series] {
        (0..<count).map {
            Series(
                id: Series.ID("s-\($0)"),
                playlistID: "p1",
                title: "Dizi \($0)",
                streamKey: "\($0)"
            )
        }
    }

    // MARK: - Temel akış

    func test_loadsFirstPageOnly() async {
        series.stored = makeSeries(20)

        let viewModel = makeViewModel(pageSize: 5)
        await viewModel.load()

        XCTAssertEqual(viewModel.series.count, 5)
        XCTAssertTrue(viewModel.canLoadMore)
    }

    func test_loadMoreAppendsAndStopsAtEnd() async {
        series.stored = makeSeries(7)

        let viewModel = makeViewModel(pageSize: 5)
        await viewModel.load()
        await viewModel.loadMore()

        XCTAssertEqual(viewModel.series.count, 7)
        XCTAssertFalse(viewModel.canLoadMore)
    }

    func test_noActivePlaylistShowsEmptyNotError() async {
        playlists.active = nil

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertTrue(viewModel.series.isEmpty)
        XCTAssertEqual(viewModel.state, .loaded(0))
    }

    // MARK: - Diziye özgü: favori anahtarı

    func test_seriesFavoriteUsesSeriesKeyspace() async {
        // ⚠️ Dizi oynatılabilir bir öğe DEĞİL; favori anahtarı film ve
        // kanallarınkiyle çakışmamalı.
        series.stored = makeSeries(1)

        let viewModel = makeViewModel()
        await viewModel.load()
        await waitUntil("dizi listesi gelmeli") { !viewModel.series.isEmpty }

        let item = viewModel.series[0]
        await viewModel.toggleFavorite(item)
        await waitUntil("favori durumu yansımalı") { viewModel.isFavorite(item) }
        XCTAssertEqual(favorites.lastKey, "series:s-0")
        XCTAssertNotEqual(favorites.lastKey, "movie:s-0", "Film anahtarıyla karışmamalı")
    }

    // MARK: - Arama

    func test_searchReplacesListAndStopsPagination() async {
        series.stored = makeSeries(20)
        series.searchResults = [
            Series(id: "found", playlistID: "p1", title: "Bulundu", streamKey: "9")
        ]

        let viewModel = makeViewModel(pageSize: 5)
        await viewModel.load()

        viewModel.searchText = "bul"
        await waitUntil("arama sonuçları listeye yansımalı") {
            viewModel.series.map(\.title) == ["Bulundu"]
        }

        XCTAssertEqual(viewModel.series.map(\.title), ["Bulundu"])
        XCTAssertFalse(viewModel.canLoadMore)
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

private final class StubSeries: SeriesRepository, @unchecked Sendable {

    var stored: [Series] = []
    var searchResults: [Series] = []

    func categories(playlistID: Playlist.ID) async throws -> [MediaCategory] { [] }

    func series(
        playlistID: Playlist.ID,
        categoryID: MediaCategory.ID?,
        limit: Int,
        offset: Int
    ) async throws -> [Series] {
        Array(stored.dropFirst(offset).prefix(limit))
    }

    func series(id: Series.ID) async throws -> Series? { stored.first { $0.id == id } }
    func seasons(seriesID: Series.ID) async throws -> [Season] { [] }

    func episodes(seriesID: Series.ID, seasonNumber: Int) async throws -> [Episode] {
        []
    }

    func episode(id: Episode.ID) async throws -> Episode? { nil }





    func loadDetails(id: Series.ID) async throws {}
    func invalidateDetails(id: Series.ID) async throws {}

    func search(query: String, playlistID: Playlist.ID, limit: Int) async throws -> [Series] {
        searchResults
    }
    func recentlyAdded(playlistID: Playlist.ID, limit: Int) async throws -> [Series] { [] }
}

private final class StubFavorites: FavoritesRepository, @unchecked Sendable {

    private var keys: Set<String> = []
    private(set) var lastKey: String?
    private var continuation: AsyncStream<Set<String>>.Continuation?

    func isFavorite(_ target: FavoriteTarget) async throws -> Bool {
        keys.contains(target.storageKey)
    }

    func toggle(_ target: FavoriteTarget) async throws -> Bool {
        let key = target.storageKey
        lastKey = key
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
