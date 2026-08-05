import XCTest
import OctopusDomain
@testable import FeatureSearch

/// Birleşik arama: üç tür paralel, kısmi başarı, geciktirme.
@MainActor
final class SearchViewModelTests: XCTestCase {

    private var playlists: StubPlaylists!
    private var channels: StubChannels!
    private var vod: StubVOD!
    private var series: StubSeries!

    override func setUp() async throws {
        playlists = StubPlaylists()
        channels = StubChannels()
        vod = StubVOD()
        series = StubSeries()
    }

    private func makeViewModel() -> SearchViewModel {
        SearchViewModel(
            dependencies: SearchDependencies(
                playlists: playlists,
                channels: channels,
                vod: vod,
                series: series
            ),
            debounce: .milliseconds(10)
        )
    }

    private func waitABit(_ ms: UInt64 = 120) async {
        try? await Task.sleep(nanoseconds: ms * 1_000_000)
    }

    // MARK: - Temel akış

    func test_searchesAllThreeKinds() async {
        channels.results = [Channel(id: "c1", playlistID: "p1", name: "Spor TV", streamKey: "1")]
        vod.results = [Movie(id: "m1", playlistID: "p1", title: "Spor Filmi", streamKey: "1")]
        series.results = [Series(id: "s1", playlistID: "p1", title: "Spor Dizisi", streamKey: "1")]

        let viewModel = makeViewModel()
        await viewModel.prepare()
        viewModel.searchText = "spor"
        await waitABit()

        XCTAssertEqual(viewModel.channels.count, 1)
        XCTAssertEqual(viewModel.movies.count, 1)
        XCTAssertEqual(viewModel.series.count, 1)
        XCTAssertEqual(viewModel.state, .loaded(3))
    }

    func test_emptyQueryShowsPrompt() async {
        let viewModel = makeViewModel()
        await viewModel.prepare()

        XCTAssertFalse(viewModel.hasQuery)
        XCTAssertEqual(viewModel.state, .idle)
    }

    func test_singleCharacterQueryIsIgnored() async {
        // Tek harf neredeyse tüm katalogla eşleşir; sonuç işe yaramaz.
        let viewModel = makeViewModel()
        await viewModel.prepare()

        viewModel.searchText = "s"
        await waitABit()

        XCTAssertTrue(channels.queries.isEmpty, "Tek harf için sorgu atılmamalı")
    }

    func test_searchIsDebounced() async {
        channels.results = [Channel(id: "c1", playlistID: "p1", name: "Sonuç", streamKey: "1")]

        let viewModel = makeViewModel()
        await viewModel.prepare()

        viewModel.searchText = "sp"
        viewModel.searchText = "spo"
        viewModel.searchText = "spor"
        await waitABit()

        XCTAssertEqual(channels.queries, ["spor"], "Yalnızca son sorgu çalışmalı")
    }

    // MARK: - Kısmi başarı

    func test_oneKindFailingDoesNotHideOthers() async {
        // Film paketi olmayan hesapta VOD araması hata verir;
        // kanal sonuçları yine de gösterilmeli.
        channels.results = [Channel(id: "c1", playlistID: "p1", name: "Kanal", streamKey: "1")]
        vod.error = AppError.notFound
        series.error = AppError.notFound

        let viewModel = makeViewModel()
        await viewModel.prepare()
        viewModel.searchText = "kanal"
        await waitABit()

        XCTAssertEqual(viewModel.channels.count, 1)
        XCTAssertTrue(viewModel.movies.isEmpty)
        XCTAssertFalse(viewModel.isEmpty)
    }

    func test_noResultsShowsEmptyState() async {
        let viewModel = makeViewModel()
        await viewModel.prepare()
        viewModel.searchText = "bulunamaz"
        await waitABit()

        XCTAssertTrue(viewModel.isEmpty)
        XCTAssertEqual(viewModel.state, .loaded(0))
    }

    // MARK: - Temizleme

    func test_clearingSearchResetsResults() async {
        channels.results = [Channel(id: "c1", playlistID: "p1", name: "Kanal", streamKey: "1")]

        let viewModel = makeViewModel()
        await viewModel.prepare()
        viewModel.searchText = "kanal"
        await waitABit()
        XCTAssertFalse(viewModel.isEmpty)

        viewModel.searchText = ""
        await waitABit()

        XCTAssertTrue(viewModel.isEmpty)
        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertFalse(viewModel.hasQuery)
    }

    // MARK: - Kaynak yok

    func test_noActivePlaylistYieldsNoResults() async {
        playlists.active = nil
        channels.results = [Channel(id: "c1", playlistID: "p1", name: "Kanal", streamKey: "1")]

        let viewModel = makeViewModel()
        await viewModel.prepare()
        viewModel.searchText = "kanal"
        await waitABit()

        XCTAssertTrue(viewModel.isEmpty)
        XCTAssertTrue(channels.queries.isEmpty, "Kaynak yokken sorgu atılmamalı")
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

private final class StubChannels: ChannelRepository, @unchecked Sendable {

    var results: [Channel] = []
    private(set) var queries: [String] = []

    func categories(playlistID: Playlist.ID) async throws -> [MediaCategory] { [] }
    func channels(playlistID: Playlist.ID, categoryID: MediaCategory.ID?) async throws -> [Channel] { [] }
    func channel(id: Channel.ID) async throws -> Channel? { nil }

    func search(query: String, playlistID: Playlist.ID, limit: Int) async throws -> [Channel] {
        queries.append(query)
        return results
    }

    func observeChannels(
        playlistID: Playlist.ID,
        categoryID: MediaCategory.ID?
    ) -> AsyncStream<[Channel]> {
        AsyncStream { $0.finish() }
    }
}

private final class StubVOD: VODRepository, @unchecked Sendable {

    var results: [Movie] = []
    var error: Error?

    func categories(playlistID: Playlist.ID) async throws -> [MediaCategory] { [] }
    func movies(
        playlistID: Playlist.ID,
        categoryID: MediaCategory.ID?,
        limit: Int,
        offset: Int
    ) async throws -> [Movie] { [] }
    func movie(id: Movie.ID) async throws -> Movie? { nil }
    func loadDetails(id: Movie.ID) async throws -> Movie { throw AppError.notFound }

    func search(query: String, playlistID: Playlist.ID, limit: Int) async throws -> [Movie] {
        if let error { throw error }
        return results
    }

    func recentlyAdded(playlistID: Playlist.ID, limit: Int) async throws -> [Movie] { [] }
}

private final class StubSeries: SeriesRepository, @unchecked Sendable {

    var results: [Series] = []
    var error: Error?

    func categories(playlistID: Playlist.ID) async throws -> [MediaCategory] { [] }
    func series(
        playlistID: Playlist.ID,
        categoryID: MediaCategory.ID?,
        limit: Int,
        offset: Int
    ) async throws -> [Series] { [] }
    func series(id: Series.ID) async throws -> Series? { nil }
    func seasons(seriesID: Series.ID) async throws -> [Season] { [] }
    func episodes(seriesID: Series.ID, seasonNumber: Int) async throws -> [Episode] { [] }
    func episode(id: Episode.ID) async throws -> Episode? { nil }
    func loadDetails(id: Series.ID) async throws {}
    func invalidateDetails(id: Series.ID) async throws {}

    func search(query: String, playlistID: Playlist.ID, limit: Int) async throws -> [Series] {
        if let error { throw error }
        return results
    }
}
