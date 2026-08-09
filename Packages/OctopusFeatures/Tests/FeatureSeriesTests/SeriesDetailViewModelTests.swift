import XCTest
import OctopusDomain
@testable import FeatureSeries

/// Dizi detayı: sezon seçimi, bölüm listesi, "devam et" mantığı.
@MainActor
final class SeriesDetailViewModelTests: XCTestCase {

    private var series: DetailStubSeries!
    private var favorites: DetailStubFavorites!
    private var progress: DetailStubProgress!

    private let seriesID = Series.ID("s1")

    override func setUp() async throws {
        series = DetailStubSeries()
        favorites = DetailStubFavorites()
        progress = DetailStubProgress()

        series.stored = [
            Series(id: seriesID, playlistID: "p1", title: "Dizi", streamKey: "77")
        ]
    }

    private func makeViewModel() -> SeriesDetailViewModel {
        SeriesDetailViewModel(
            seriesID: seriesID,
            dependencies: SeriesDependencies(
                playlists: DetailStubPlaylists(),
                series: series,
                favorites: favorites,
                progress: progress
            )
        )
    }

    private func makeEpisode(_ number: Int, season: Int = 1) -> Episode {
        Episode(
            id: Episode.ID("e-\(season)-\(number)"),
            seriesID: seriesID,
            seasonNumber: season,
            number: number,
            title: "Bölüm \(number)",
            streamKey: "\(number)"
        )
    }

    private func makeSeason(_ number: Int) -> Season {
        Season(id: Season.ID("s-\(number)"), seriesID: seriesID, number: number)
    }

    // MARK: - Yükleme

    func test_loadSelectsFirstSeasonAutomatically() async {
        // Kullanıcı boş ekranla karşılaşmamalı.
        series.seasonList = [makeSeason(1), makeSeason(2)]
        series.episodesBySeason = [1: [makeEpisode(1), makeEpisode(2)]]

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertEqual(viewModel.selectedSeasonNumber, 1)
        XCTAssertEqual(viewModel.episodes.count, 2)
        XCTAssertEqual(series.loadDetailsCount, 1, "Ağaç bir kez istenmeli")
    }

    func test_seasonSwitchLoadsThatSeason() async {
        series.seasonList = [makeSeason(1), makeSeason(2)]
        series.episodesBySeason = [
            1: [makeEpisode(1)],
            2: [makeEpisode(1, season: 2), makeEpisode(2, season: 2)]
        ]

        let viewModel = makeViewModel()
        await viewModel.load()
        await viewModel.selectSeason(2)

        XCTAssertEqual(viewModel.selectedSeasonNumber, 2)
        XCTAssertEqual(viewModel.episodes.count, 2)
    }

    func test_missingSeriesReportsNotFound() async {
        series.stored = []

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertEqual(viewModel.state, .failed(.notFound))
    }

    func test_emptyTreeShowsEmptyStateNotError() async {
        // Sağlayıcıda bölüm bilgisi olmayabilir; bu bir çökme sebebi değil.
        series.seasonList = []

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertTrue(viewModel.seasons.isEmpty)
        XCTAssertEqual(viewModel.state, .loaded(0))
    }

    // MARK: - Devam et

    func test_resumePrefersPartiallyWatchedEpisode() async {
        series.seasonList = [makeSeason(1)]
        series.episodesBySeason = [1: [makeEpisode(1), makeEpisode(2), makeEpisode(3)]]
        // 1. bölüm bitmiş, 2. bölüm yarım.
        progress.fractions = ["e-1-1": 0.99, "e-1-2": 0.4]

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertEqual(viewModel.resumeEpisode?.number, 2, "Yarım bırakılan bölüm önceliklidir")
    }

    func test_resumeFallsBackToFirstUnwatched() async {
        series.seasonList = [makeSeason(1)]
        series.episodesBySeason = [1: [makeEpisode(1), makeEpisode(2), makeEpisode(3)]]
        progress.fractions = ["e-1-1": 0.99, "e-1-2": 0.99]

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertEqual(viewModel.resumeEpisode?.number, 3)
    }

    func test_resumeIsFirstEpisodeWhenNothingWatched() async {
        series.seasonList = [makeSeason(1)]
        series.episodesBySeason = [1: [makeEpisode(1), makeEpisode(2)]]

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertEqual(viewModel.resumeEpisode?.number, 1)
    }

    func test_watchedAndProgressFlags() async {
        series.seasonList = [makeSeason(1)]
        series.episodesBySeason = [1: [makeEpisode(1), makeEpisode(2), makeEpisode(3)]]
        progress.fractions = ["e-1-1": 0.99, "e-1-2": 0.4]

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertTrue(viewModel.isWatched(viewModel.episodes[0]))
        XCTAssertNil(viewModel.progress(for: viewModel.episodes[0]), "Bitmiş bölümde çubuk yok")

        XCTAssertFalse(viewModel.isWatched(viewModel.episodes[1]))
        XCTAssertEqual(viewModel.progress(for: viewModel.episodes[1]), 0.4)

        XCTAssertNil(viewModel.progress(for: viewModel.episodes[2]), "Hiç izlenmemişte çubuk yok")
    }

    // MARK: - Yenileme ve favori

    func test_refreshInvalidatesCache() async {
        // Panelde yeni bölüm yayınlanmış olabilir; önbellek onu göstermez.
        series.seasonList = [makeSeason(1)]
        series.episodesBySeason = [1: [makeEpisode(1)]]

        let viewModel = makeViewModel()
        await viewModel.load()
        await viewModel.refresh()

        XCTAssertEqual(series.invalidateCount, 1)
        XCTAssertEqual(series.loadDetailsCount, 2)
    }

    func test_toggleFavorite() async {
        series.seasonList = [makeSeason(1)]
        series.episodesBySeason = [1: [makeEpisode(1)]]

        let viewModel = makeViewModel()
        await viewModel.load()
        XCTAssertFalse(viewModel.isFavorite)

        await viewModel.toggleFavorite()
        XCTAssertTrue(viewModel.isFavorite)
        XCTAssertEqual(favorites.lastKey, "series:s1")
    }
}

// MARK: - Sahteler

private final class DetailStubPlaylists: PlaylistRepository, @unchecked Sendable {
    func all() async throws -> [Playlist] { [] }
    func playlist(id: Playlist.ID) async throws -> Playlist? { nil }
    func activePlaylist() async throws -> Playlist? { nil }
    func add(_ playlist: Playlist, password: String?) async throws {}
    func update(_ playlist: Playlist) async throws {}
    func setActive(id: Playlist.ID) async throws {}
    func delete(id: Playlist.ID) async throws {}
}

private final class DetailStubSeries: SeriesRepository, @unchecked Sendable {

    var stored: [Series] = []
    var seasonList: [Season] = []
    var episodesBySeason: [Int: [Episode]] = [:]

    private(set) var loadDetailsCount = 0
    private(set) var invalidateCount = 0

    func categories(playlistID: Playlist.ID) async throws -> [MediaCategory] { [] }

    func series(
        playlistID: Playlist.ID,
        categoryID: MediaCategory.ID?,
        limit: Int,
        offset: Int
    ) async throws -> [Series] { stored }

    func series(id: Series.ID) async throws -> Series? { stored.first { $0.id == id } }
    func seasons(seriesID: Series.ID) async throws -> [Season] { seasonList }

    func episodes(seriesID: Series.ID, seasonNumber: Int) async throws -> [Episode] {
        episodesBySeason[seasonNumber] ?? []
    }

    func episode(id: Episode.ID) async throws -> Episode? { nil }
    func loadDetails(id: Series.ID) async throws { loadDetailsCount += 1 }
    func invalidateDetails(id: Series.ID) async throws { invalidateCount += 1 }

    func search(query: String, playlistID: Playlist.ID, limit: Int) async throws -> [Series] { [] }
    func recentlyAdded(playlistID: Playlist.ID, limit: Int) async throws -> [Series] { [] }
}

private final class DetailStubFavorites: FavoritesRepository, @unchecked Sendable {

    private var keys: Set<String> = []
    private(set) var lastKey: String?

    func isFavorite(_ target: FavoriteTarget) async throws -> Bool {
        keys.contains(target.storageKey)
    }

    func toggle(_ target: FavoriteTarget) async throws -> Bool {
        let key = target.storageKey
        lastKey = key
        if keys.contains(key) { keys.remove(key); return false }
        keys.insert(key)
        return true
    }

    func favoriteChannels(playlistID: Playlist.ID) async throws -> [Channel] { [] }
    func favoriteMovies(playlistID: Playlist.ID) async throws -> [Movie] { [] }
    func favoriteSeries(playlistID: Playlist.ID) async throws -> [Series] { [] }
    func observeFavoriteKeys() -> AsyncStream<Set<String>> { AsyncStream { $0.finish() } }
}

private final class DetailStubProgress: PlaybackProgressRepository, @unchecked Sendable {

    /// Bölüm kimliği → izlenme oranı.
    var fractions: [String: Double] = [:]

    func progress(for source: PlaybackItem.Source) async throws -> PlaybackProgress? {
        guard case .episode(let id) = source,
              let fraction = fractions[id.value]
        else { return nil }

        return PlaybackProgress(
            itemKey: source.storageKey,
            positionSeconds: fraction * 1_000,
            durationSeconds: 1_000,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    func save(_ progress: PlaybackProgress, for source: PlaybackItem.Source) async throws {}
    func continueWatching(playlistID: Playlist.ID, limit: Int) async throws -> [PlaybackProgress] { [] }
    func clear(for source: PlaybackItem.Source) async throws {}
    func clearAll() async throws {}
}
