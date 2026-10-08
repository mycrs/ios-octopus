import XCTest
import OctopusDomain
@testable import OctopusData

final class SampleLibraryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_456_000)

    private func source(id: Playlist.ID = SampleLibraryCatalog.playlistID) -> Playlist {
        Playlist(id: id, name: SampleLibraryCatalog.playlistName, kind: .sampleLibrary, createdAt: now)
    }

    func test_sampleSourceRoundTripsWithoutCredentialsOrExternalAddress() async throws {
        let database = try AppDatabase.makeInMemory()
        let secrets = FakeSecretStore()
        let repository = GRDBPlaylistRepository(database: database, secrets: secrets)
        let sample = source()

        try await repository.add(sample, password: nil)

        let stored = try await repository.playlist(id: sample.id)
        XCTAssertEqual(stored?.kind, .sampleLibrary)
        XCTAssertNil(stored?.epgURL)
        XCTAssertNil(try secrets.read(for: sample.credentialKey))
    }

    func test_sampleSyncCreatesAllCatalogsAndScopedGuideWithoutNetworkRequests() async throws {
        let database = try AppDatabase.makeInMemory()
        let secrets = FakeSecretStore()
        let repository = GRDBPlaylistRepository(database: database, secrets: secrets)
        try await repository.add(source(), password: nil)
        let requests = LockedBox(0)
        let http = StubHTTPClient { _ in
            requests.set(requests.get() + 1)
            throw AppError.network(reason: "Örnek katalog kurulumu ağ isteği yapmamalı")
        }
        let factory = DefaultContentProviderFactory(httpClient: http, secrets: secrets)
        let service = ContentSyncService(playlists: repository, providerFactory: factory,
                                         database: database, httpClient: http, now: { self.now })

        try await service.sync(playlistID: SampleLibraryCatalog.playlistID)

        let health = try await GRDBSourceHealthReader(database: database)
            .snapshot(playlistID: SampleLibraryCatalog.playlistID, at: now)
        XCTAssertEqual(health.sourceKind, .sampleLibrary)
        XCTAssertEqual(health.channels, 2)
        XCTAssertEqual(health.movies, 2)
        XCTAssertEqual(health.series, 1)
        XCTAssertEqual(health.channelsWithoutGuide, 0)
        let guide = try await GRDBEPGRepository(database: database)
            .allNowPlaying(playlistID: SampleLibraryCatalog.playlistID, at: now)
        XCTAssertEqual(guide.count, 2)
        XCTAssertTrue(guide.values.allSatisfy { $0.title.contains("Örnek") })
        XCTAssertEqual(requests.get(), 0, "Katalog veya rehber kurulumu film/ağ indirmesi yapmamalı")
    }

    func test_sampleChannelIsRecordedPlaybackAndDoesNotClaimToBeLive() async throws {
        let database = try AppDatabase.makeInMemory()
        let repository = GRDBPlaylistRepository(database: database, secrets: FakeSecretStore())
        try await repository.add(source(), password: nil)
        let provider = SampleLibraryContentProvider(playlistID: SampleLibraryCatalog.playlistID)
        let resolver = ProviderStreamResolver(
            playlists: repository, providerFactory: FakeProviderFactory(provider: provider),
            progress: GRDBPlaybackProgressRepository(database: database)
        )
        let channels = try await provider.fetchChannels(categoryID: nil)
        let channel = try XCTUnwrap(channels.first)

        let item = try await resolver.playbackItem(for: channel)

        XCTAssertFalse(item.isLive, "Örnek kayıt gerçek canlı yayın gibi yeniden bağlanmamalı")
        XCTAssertEqual(item.format, .mp4)
        XCTAssertTrue(item.headers.isEmpty)
        XCTAssertTrue(item.title.contains("Örnek"))
    }

    func test_sampleCollectionUsesTheSameFullFilmsAsMovieLibrary() async throws {
        let provider = SampleLibraryContentProvider(playlistID: SampleLibraryCatalog.playlistID)
        let movies = try await provider.fetchMovies(categoryID: nil)
        let series = try await provider.fetchSeries(categoryID: nil)
        let collection = try XCTUnwrap(series.first)
        let details = try await provider.fetchSeriesDetails(streamKey: collection.streamKey)

        XCTAssertEqual(details.seasons.count, 1)
        XCTAssertEqual(details.episodes.count, movies.count)
        XCTAssertTrue(collection.title.contains("Örnek"))
        for (movie, episode) in zip(movies, details.episodes) {
            XCTAssertEqual(provider.streamURL(for: movie), provider.streamURL(for: episode))
            XCTAssertEqual(episode.durationSeconds, movie.durationSeconds)
            XCTAssertGreaterThan(episode.durationSeconds ?? 0, 500, "Kısa fragman tam film diye sunulmamalı")
            XCTAssertTrue(movie.plot?.contains("Blender Foundation") == true)
            XCTAssertTrue(episode.plot?.contains("Attribution 3.0") == true)
        }
    }

    func test_sampleIdentityIsStableAndSeparateFromOtherSources() async throws {
        let first = SampleLibraryContentProvider(playlistID: "sample-a")
        let second = SampleLibraryContentProvider(playlistID: "sample-b")
        let initial = try await first.fetchMovies(categoryID: nil)
        let reloaded = try await first.fetchMovies(categoryID: nil)
        let other = try await second.fetchMovies(categoryID: nil)

        XCTAssertEqual(initial.map(\.id), reloaded.map(\.id))
        XCTAssertTrue(Set(initial.map(\.id)).isDisjoint(with: Set(other.map(\.id))))
    }

    func test_unknownOrForeignMediaCannotEscapeSampleAllowlist() async throws {
        let provider = SampleLibraryContentProvider(playlistID: SampleLibraryCatalog.playlistID)
        let foreign = Movie(id: "foreign", playlistID: "personal", title: "Yabancı", streamKey: "big-buck-bunny")
        let injected = Movie(id: "injected", playlistID: SampleLibraryCatalog.playlistID,
                             title: "Geçersiz", streamKey: "https://other.example.com/video.mp4")

        XCTAssertNil(provider.streamURL(for: foreign))
        XCTAssertNil(provider.streamURL(for: injected))
        do {
            _ = try await provider.fetchSeriesDetails(streamKey: "unknown")
            XCTFail("Geçersiz seçki anahtarı kabul edilmemeli")
        } catch { XCTAssertEqual(error as? AppError, .notFound) }
    }
}
