import XCTest
import OctopusDomain
@testable import FeatureVOD

/// Film detayı: künye yükleme, devam etme, favori.
@MainActor
final class MovieDetailViewModelTests: XCTestCase {

    private var vod: DetailStubVOD!
    private var favorites: DetailStubFavorites!
    private var progress: DetailStubProgress!

    private let movieID = Movie.ID("m1")

    override func setUp() async throws {
        vod = DetailStubVOD()
        favorites = DetailStubFavorites()
        progress = DetailStubProgress()
    }

    private func makeViewModel() -> MovieDetailViewModel {
        MovieDetailViewModel(
            movieID: movieID,
            dependencies: VODDependencies(
                playlists: DetailStubPlaylists(),
                vod: vod,
                favorites: favorites,
                progress: progress
            )
        )
    }

    private func makeMovie(
        title: String = "Film",
        duration: Int? = nil,
        year: Int? = nil,
        genres: [String] = []
    ) -> Movie {
        var releaseDate: Date?
        if let year {
            var components = DateComponents()
            components.year = year
            components.month = 1
            components.day = 1
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            releaseDate = calendar.date(from: components)
        }

        return Movie(
            id: movieID,
            playlistID: "p1",
            title: title,
            streamKey: "1",
            releaseDate: releaseDate,
            durationSeconds: duration,
            genres: genres
        )
    }

    // MARK: - Yükleme

    func test_loadFetchesDetails() async {
        vod.detail = makeMovie(title: "Zenginleştirilmiş")

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertEqual(viewModel.movie?.title, "Zenginleştirilmiş")
        XCTAssertEqual(vod.loadDetailsCount, 1)
        XCTAssertEqual(viewModel.state, .loaded(true))
    }

    func test_missingMovieReportsError() async {
        vod.error = AppError.notFound

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertEqual(viewModel.state, .failed(.notFound))
    }

    // MARK: - Devam etme

    func test_partiallyWatchedShowsResume() async {
        vod.detail = makeMovie()
        progress.fraction = 0.35

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertEqual(viewModel.resumeFraction, 0.35)
        XCTAssertEqual(viewModel.playButtonTitle, "Devam et")
    }

    func test_finishedMovieOffersFreshStart() async {
        // %95 üstü izlenmiş film "devam et" değil "oynat" demeli.
        vod.detail = makeMovie()
        progress.fraction = 0.98

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertNil(viewModel.resumeFraction)
        XCTAssertEqual(viewModel.playButtonTitle, "Oynat")
    }

    func test_unwatchedMovieOffersPlay() async {
        vod.detail = makeMovie()

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertNil(viewModel.resumeFraction)
        XCTAssertEqual(viewModel.playButtonTitle, "Oynat")
    }

    func test_resetProgressClearsResume() async {
        vod.detail = makeMovie()
        progress.fraction = 0.5

        let viewModel = makeViewModel()
        await viewModel.load()
        await viewModel.resetProgress()

        XCTAssertNil(viewModel.resumeFraction)
        XCTAssertEqual(viewModel.playButtonTitle, "Oynat")
        XCTAssertTrue(progress.wasCleared)
    }

    // MARK: - Künye satırı

    func test_metadataLineCombinesAvailableFields() async {
        vod.detail = makeMovie(duration: 6_420, year: 2020, genres: ["Dram", "Gerilim"])

        let viewModel = makeViewModel()
        await viewModel.load()

        // 6420 sn = 1 saat 47 dakika
        XCTAssertEqual(viewModel.metadataLine, "2020 · 1s 47dk · Dram, Gerilim")
    }

    func test_metadataLineOmitsMissingFields() async {
        vod.detail = makeMovie(duration: 2_700)

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertEqual(viewModel.metadataLine, "45dk", "Bir saatin altında saat gösterilmemeli")
    }

    func test_metadataLineIsNilWhenNothingKnown() async {
        vod.detail = makeMovie()

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertNil(viewModel.metadataLine)
    }

    // MARK: - Favori

    func test_toggleFavorite() async {
        vod.detail = makeMovie()

        let viewModel = makeViewModel()
        await viewModel.load()
        XCTAssertFalse(viewModel.isFavorite)

        await viewModel.toggleFavorite()
        XCTAssertTrue(viewModel.isFavorite)
        XCTAssertEqual(favorites.lastKey, "movie:m1")
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

private final class DetailStubVOD: VODRepository, @unchecked Sendable {

    var detail: Movie?
    var error: Error?
    private(set) var loadDetailsCount = 0

    func categories(playlistID: Playlist.ID) async throws -> [MediaCategory] { [] }

    func movies(
        playlistID: Playlist.ID,
        categoryID: MediaCategory.ID?,
        limit: Int,
        offset: Int
    ) async throws -> [Movie] { [] }

    func movie(id: Movie.ID) async throws -> Movie? { detail }

    func loadDetails(id: Movie.ID) async throws -> Movie {
        loadDetailsCount += 1
        if let error { throw error }
        guard let detail else { throw AppError.notFound }
        return detail
    }

    func search(query: String, playlistID: Playlist.ID, limit: Int) async throws -> [Movie] { [] }
    func recentlyAdded(playlistID: Playlist.ID, limit: Int) async throws -> [Movie] { [] }
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

    var fraction: Double?
    private(set) var wasCleared = false

    func progress(for source: PlaybackItem.Source) async throws -> PlaybackProgress? {
        guard let fraction else { return nil }
        return PlaybackProgress(
            itemKey: source.storageKey,
            positionSeconds: fraction * 1_000,
            durationSeconds: 1_000,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    func save(_ progress: PlaybackProgress, for source: PlaybackItem.Source) async throws {}
    func continueWatching(playlistID: Playlist.ID, limit: Int) async throws -> [PlaybackProgress] { [] }

    func clear(for source: PlaybackItem.Source) async throws {
        wasCleared = true
        fraction = nil
    }

    func clearAll() async throws {}
}
