import XCTest
import OctopusDomain
@testable import FeatureHome

/// Ana sayfa rafları: ilerleme kayıtlarının içeriğe bağlanması.
@MainActor
final class HomeViewModelTests: XCTestCase {

    private var playlists: StubPlaylists!
    private var vod: StubVOD!
    private var series: StubSeries!
    private var progress: StubProgress!
    private var history: StubHistory!

    override func setUp() async throws {
        playlists = StubPlaylists()
        vod = StubVOD()
        series = StubSeries()
        progress = StubProgress()
        history = StubHistory()
    }

    private func makeViewModel() -> HomeViewModel {
        HomeViewModel(
            dependencies: HomeDependencies(
                playlists: playlists,
                channels: StubChannels(),
                vod: vod,
                series: series,
                progress: progress,
                history: history
            )
        )
    }

    private func makeProgress(key: String, fraction: Double) -> PlaybackProgress {
        PlaybackProgress(
            itemKey: key,
            positionSeconds: fraction * 1_000,
            durationSeconds: 1_000,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    // MARK: - İzlemeye devam et

    func test_movieProgressBecomesResumeItem() async {
        vod.movies = [
            Movie(id: "m1", playlistID: "p1", title: "Film", streamKey: "1")
        ]
        progress.items = [makeProgress(key: "movie:m1", fraction: 0.4)]

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertEqual(viewModel.resumeItems.count, 1)
        XCTAssertEqual(viewModel.resumeItems[0].title, "Film")
        XCTAssertEqual(viewModel.resumeItems[0].fraction, 0.4)
        XCTAssertNil(viewModel.resumeItems[0].subtitle, "Filmde alt başlık yok")
    }

    func test_episodeProgressUsesSeriesTitleAndEpisodeLabel() async {
        // Kullanıcı rafta dizi adını görmeli, bölüm adını değil.
        series.seriesList = [
            Series(id: "s1", playlistID: "p1", title: "Dizi Adı", streamKey: "77")
        ]
        series.episodeList = [
            Episode(
                id: "e1",
                seriesID: "s1",
                seasonNumber: 2,
                number: 7,
                title: "Bölüm Adı",
                streamKey: "101"
            )
        ]
        progress.items = [makeProgress(key: "episode:e1", fraction: 0.6)]

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertEqual(viewModel.resumeItems[0].title, "Dizi Adı")
        XCTAssertEqual(viewModel.resumeItems[0].subtitle, "S02B07")
    }

    func test_deletedContentIsSkipped() async {
        // Katalogdan kaldırılmış içeriğin kaydı rafta görünmemeli;
        // kullanıcı var olmayan bir filme tıklayamamalı.
        progress.items = [
            makeProgress(key: "movie:silinmis", fraction: 0.3),
            makeProgress(key: "movie:m1", fraction: 0.5)
        ]
        vod.movies = [
            Movie(id: "m1", playlistID: "p1", title: "Var Olan", streamKey: "1")
        ]

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertEqual(viewModel.resumeItems.map(\.title), ["Var Olan"])
    }

    func test_liveChannelProgressIsIgnored() async {
        // Canlı yayında "kaldığın yer" kavramı yok.
        progress.items = [makeProgress(key: "live:c1", fraction: 0.5)]

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertTrue(viewModel.resumeItems.isEmpty)
    }

    func test_malformedKeyIsSkipped() async {
        progress.items = [
            makeProgress(key: "bozuk-anahtar", fraction: 0.5),
            makeProgress(key: "movie:m1", fraction: 0.5)
        ]
        vod.movies = [Movie(id: "m1", playlistID: "p1", title: "Film", streamKey: "1")]

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertEqual(viewModel.resumeItems.count, 1)
    }

    // MARK: - Diğer raflar

    func test_allShelvesAreLoaded() async {
        progress.items = [makeProgress(key: "movie:m1", fraction: 0.4)]
        vod.movies = [Movie(id: "m1", playlistID: "p1", title: "Film", streamKey: "1")]
        vod.recent = [Movie(id: "m2", playlistID: "p1", title: "Yeni Film", streamKey: "2")]
        history.channels = [
            Channel(id: "c1", playlistID: "p1", name: "TRT 1", streamKey: "1")
        ]

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertEqual(viewModel.resumeItems.count, 1)
        XCTAssertEqual(viewModel.recentlyAdded.count, 1)
        XCTAssertEqual(viewModel.recentChannels.count, 1)
        XCTAssertFalse(viewModel.isEmpty)
    }

    func test_oneShelfFailingDoesNotBreakOthers() async {
        // Film paketi olmayan hesapta "son eklenenler" hata verebilir;
        // diğer raflar yine de görünmeli.
        vod.recentError = AppError.notFound
        history.channels = [
            Channel(id: "c1", playlistID: "p1", name: "TRT 1", streamKey: "1")
        ]

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertTrue(viewModel.recentlyAdded.isEmpty)
        XCTAssertEqual(viewModel.recentChannels.count, 1)
        XCTAssertFalse(viewModel.isEmpty)
    }

    func test_noActivePlaylistShowsEmpty() async {
        playlists.active = nil

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertTrue(viewModel.isEmpty)
        XCTAssertEqual(viewModel.state, .loaded(0))
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

    var movies: [Movie] = []
    var recent: [Movie] = []
    var recentError: Error?

    func categories(playlistID: Playlist.ID) async throws -> [MediaCategory] { [] }

    func movies(
        playlistID: Playlist.ID,
        categoryID: MediaCategory.ID?,
        limit: Int,
        offset: Int
    ) async throws -> [Movie] { movies }

    func movie(id: Movie.ID) async throws -> Movie? { movies.first { $0.id == id } }
    func loadDetails(id: Movie.ID) async throws -> Movie { throw AppError.notFound }
    func search(query: String, playlistID: Playlist.ID, limit: Int) async throws -> [Movie] { [] }

    func recentlyAdded(playlistID: Playlist.ID, limit: Int) async throws -> [Movie] {
        if let recentError { throw recentError }
        return recent
    }
}

private final class StubSeries: SeriesRepository, @unchecked Sendable {

    var seriesList: [Series] = []
    var episodeList: [Episode] = []

    func categories(playlistID: Playlist.ID) async throws -> [MediaCategory] { [] }

    func series(
        playlistID: Playlist.ID,
        categoryID: MediaCategory.ID?,
        limit: Int,
        offset: Int
    ) async throws -> [Series] { seriesList }

    func series(id: Series.ID) async throws -> Series? { seriesList.first { $0.id == id } }
    func seasons(seriesID: Series.ID) async throws -> [Season] { [] }
    func episodes(seriesID: Series.ID, seasonNumber: Int) async throws -> [Episode] { [] }
    func episode(id: Episode.ID) async throws -> Episode? { episodeList.first { $0.id == id } }
    func loadDetails(id: Series.ID) async throws {}
    func invalidateDetails(id: Series.ID) async throws {}
    func search(query: String, playlistID: Playlist.ID, limit: Int) async throws -> [Series] { [] }
}

private final class StubProgress: PlaybackProgressRepository, @unchecked Sendable {

    var items: [PlaybackProgress] = []

    func progress(for source: PlaybackItem.Source) async throws -> PlaybackProgress? { nil }
    func save(_ progress: PlaybackProgress, for source: PlaybackItem.Source) async throws {}

    func continueWatching(playlistID: Playlist.ID, limit: Int) async throws -> [PlaybackProgress] {
        items
    }

    func clear(for source: PlaybackItem.Source) async throws {}
    func clearAll() async throws {}
}

private final class StubHistory: WatchHistoryRepository, @unchecked Sendable {

    var channels: [Channel] = []

    func record(_ source: PlaybackItem.Source, at date: Date) async throws {}
    func recentChannels(playlistID: Playlist.ID, limit: Int) async throws -> [Channel] { channels }
    func clearAll() async throws {}
}

private struct StubChannels: ChannelRepository {
    func categories(playlistID: Playlist.ID) async throws -> [MediaCategory] { [] }
    func channels(playlistID: Playlist.ID, categoryID: MediaCategory.ID?) async throws -> [Channel] { [] }
    func channel(id: Channel.ID) async throws -> Channel? { nil }
    func search(query: String, playlistID: Playlist.ID, limit: Int) async throws -> [Channel] { [] }
    func observeChannels(
        playlistID: Playlist.ID,
        categoryID: MediaCategory.ID?
    ) -> AsyncStream<[Channel]> {
        AsyncStream { $0.finish() }
    }
}
