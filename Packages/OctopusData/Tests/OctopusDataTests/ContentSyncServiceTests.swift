import XCTest
import OctopusDomain
@testable import OctopusData

/// Senkronizasyon: katalog değiştirme, kısmi başarı, ilerleme ve iptal.
final class ContentSyncServiceTests: XCTestCase {

    private var database: AppDatabase!
    private var playlists: GRDBPlaylistRepository!
    private var channels: GRDBChannelRepository!
    private var favorites: GRDBFavoritesRepository!

    override func setUp() async throws {
        database = try AppDatabase.makeInMemory()
        playlists = GRDBPlaylistRepository(database: database, secrets: FakeSecretStore())
        channels = GRDBChannelRepository(database: database)
        favorites = GRDBFavoritesRepository(database: database)

        try await playlists.add(
            Playlist(
                id: "p1",
                name: "Kaynak",
                kind: .m3u(url: URL(string: "http://liste.example.com/p.m3u")!),
                createdAt: Date(timeIntervalSince1970: 0),
                isActive: true
            ),
            password: nil
        )
    }

    private func makeService(_ provider: ContentProvider) -> ContentSyncService {
        ContentSyncService(
            playlists: playlists,
            providerFactory: FakeProviderFactory(provider: provider),
            database: database
        )
    }

    // MARK: - Temel akış

    func test_sync_writesCatalogToDatabase() async throws {
        let provider = FakeProvider(
            channels: [
                makeChannel(id: "1", name: "TRT 1", sortOrder: 0),
                makeChannel(id: "2", name: "Show", sortOrder: 1)
            ],
            liveCategories: [makeCategory(id: "c1", name: "ULUSAL")]
        )

        try await makeService(provider).sync(playlistID: "p1")

        // Sağlayıcının liste sırası korunur — kullanıcı alıştığı düzeni görür.
        let stored = try await channels.channels(playlistID: "p1", categoryID: nil)
        XCTAssertEqual(stored.map(\.name), ["TRT 1", "Show"])

        let categories = try await channels.categories(playlistID: "p1")
        XCTAssertEqual(categories.map(\.name), ["ULUSAL"])
    }

    func test_sync_updatesLastSyncedTimestamp() async throws {
        let provider = FakeProvider(channels: [makeChannel(id: "1", name: "K")])
        try await makeService(provider).sync(playlistID: "p1")

        let fetched = try await playlists.playlist(id: "p1")
        let playlist = try XCTUnwrap(fetched)
        XCTAssertNotNil(playlist.lastSyncedAt)
    }

    // MARK: - Değiştirme stratejisi

    func test_m3uResync_downloadsFreshPlaylistOncePerSync() async throws {
        let body = LockedBox("#EXTM3U\n#EXTINF:-1,Eski kanal\nhttp://x/old.ts\n")
        let count = LockedBox(0)
        let provider = M3UContentProvider(
            sourceURL: URL(string: "http://liste.example.com/p.m3u")!,
            playlistID: "p1",
            httpClient: StubHTTPClient { _ in
                count.set(count.get() + 1)
                return Data(body.get().utf8)
            }
        )
        let service = makeService(provider)
        try await service.sync(playlistID: "p1")
        body.set("#EXTM3U\n#EXTINF:-1,Yeni kanal\nhttp://x/new.ts\n")

        try await service.sync(playlistID: "p1")

        let stored = try await channels.channels(playlistID: "p1", categoryID: nil)
        XCTAssertEqual(stored.map(\.name), ["Yeni kanal"])
        XCTAssertEqual(count.get(), 2, "Her sync içindeki aşamalar tek indirmeyi paylaşmalı")
    }

    func test_removedChannelsDisappearAfterResync() async throws {
        // Sağlayıcıdan kaldırılan kanal cihazda kalırsa kullanıcı tıkladığında
        // "yayın yok" hatası alır.
        let provider = FakeProvider(channels: [
            makeChannel(id: "1", name: "Kalıcı"),
            makeChannel(id: "2", name: "Kaldırılacak")
        ])
        let service = makeService(provider)
        try await service.sync(playlistID: "p1")

        await provider.setChannels([makeChannel(id: "1", name: "Kalıcı")])
        try await service.sync(playlistID: "p1")

        let stored = try await channels.channels(playlistID: "p1", categoryID: nil)
        XCTAssertEqual(stored.map(\.name), ["Kalıcı"])
    }

    func test_favoritesSurviveResync() async throws {
        // Favoriler katalog tablolarından bağımsız; senkronizasyon silmemeli.
        let provider = FakeProvider(channels: [makeChannel(id: "1", name: "Kanal")])
        let service = makeService(provider)
        try await service.sync(playlistID: "p1")

        let channelID = Channel.ID("p1#live#1")
        _ = try await favorites.toggle(.channel(channelID))

        try await service.sync(playlistID: "p1")

        let isFavorite = try await favorites.isFavorite(.channel(channelID))
        XCTAssertTrue(isFavorite, "Senkronizasyon favorileri silmemeli")
    }

    // MARK: - Kısmi başarı

    func test_movieFailureDoesNotFailWholeSync() async throws {
        // Xtream hesaplarının çoğunda film paketi yok; bu uç hata döner.
        // Canlı yayın alındıysa senkronizasyon başarılı sayılmalı.
        let provider = FakeProvider(
            channels: [makeChannel(id: "1", name: "Kanal")],
            movieError: AppError.notFound,
            seriesError: AppError.notFound
        )

        try await makeService(provider).sync(playlistID: "p1")

        let stored = try await channels.channels(playlistID: "p1", categoryID: nil)
        XCTAssertEqual(stored.count, 1, "Canlı katalog yazılmış olmalı")
    }

    func test_movieOnlySourceSyncsWithoutLiveEndpoint() async throws {
        let movie = Movie(id: "p1#vod#9", playlistID: "p1", title: "Film", streamKey: "9")
        let provider = FakeProvider(
            channels: [], liveError: AppError.notFound,
            movies: [movie], seriesError: AppError.notFound
        )

        try await makeService(provider).sync(playlistID: "p1")

        let stored = try await GRDBVODRepository(database: database).movie(id: movie.id)
        let playlist = try await playlists.playlist(id: "p1")
        XCTAssertEqual(stored?.title, "Film")
        XCTAssertNotNil(playlist?.lastSyncedAt)
    }

    func test_seriesOnlySourceSyncsWithoutLiveOrMovieEndpoints() async throws {
        let series = Series(id: "p1#series#7", playlistID: "p1", title: "Dizi", streamKey: "7")
        let provider = FakeProvider(
            channels: [], liveError: AppError.notFound,
            movieError: AppError.notFound, series: [series]
        )

        try await makeService(provider).sync(playlistID: "p1")

        let stored = try await GRDBSeriesRepository(database: database).series(id: series.id)
        XCTAssertEqual(stored?.title, "Dizi")
    }

    func test_failedLiveEndpointPreservesCachedChannelsWhileMoviesRefresh() async throws {
        try await makeService(FakeProvider(channels: [makeChannel(id: "1", name: "Yerel kanal")]))
            .sync(playlistID: "p1")
        let movie = Movie(id: "p1#vod#9", playlistID: "p1", title: "Yeni film", streamKey: "9")
        let provider = FakeProvider(
            channels: [], liveError: AppError.network(reason: "kopuk"), movies: [movie]
        )

        try await makeService(provider).sync(playlistID: "p1")

        let stored = try await channels.channels(playlistID: "p1", categoryID: nil)
        XCTAssertEqual(stored.map(\.name), ["Yerel kanal"], "Başarısız uç boş liste diye kaydedilmemeli")
        let storedMovie = try await GRDBVODRepository(database: database).movie(id: movie.id)
        XCTAssertEqual(storedMovie?.title, "Yeni film")
    }

    func test_allCatalogEndpointsFailWithoutMarkingSourceSynced() async throws {
        let provider = FakeProvider(
            channels: [], liveError: AppError.network(reason: "kopuk"),
            movieError: AppError.notFound, seriesError: AppError.notFound
        )

        do {
            try await makeService(provider).sync(playlistID: "p1")
            XCTFail("Hiçbir katalog alınamadığında başarı yayınlanmamalı")
        } catch {
            XCTAssertEqual(error as? AppError, .network(reason: "kopuk"))
        }

        let playlist = try await playlists.playlist(id: "p1")
        XCTAssertNil(playlist?.lastSyncedAt)
    }

    func test_failedChannelFetchPreservesCatalogAfterCategoriesSucceeded() async throws {
        try await makeService(FakeProvider(channels: [makeChannel(id: "1", name: "Yerel kanal")]))
            .sync(playlistID: "p1")
        let provider = FakeProvider(channels: [], channelError: AppError.network(reason: "kopuk"))

        try await makeService(provider).sync(playlistID: "p1")

        let stored = try await channels.channels(playlistID: "p1", categoryID: nil)
        XCTAssertEqual(stored.map(\.name), ["Yerel kanal"])
    }

    func test_storageFailureDoesNotBecomeSuccessfulPartialSync() async throws {
        // Aynı ID iki kez gelince yazım transaction'ı başarısızdır. Diğer
        // paketler alınabilir olsa bile bu kayıt hatası gizlenmemelidir.
        let duplicate = makeChannel(id: "1", name: "Kanal")
        let provider = FakeProvider(channels: [duplicate, duplicate])

        do {
            try await makeService(provider).sync(playlistID: "p1")
            XCTFail("Depo hatası başarı diye yutulmamalı")
        } catch {
            XCTAssertNotNil(error as? AppError)
        }

        let playlist = try await playlists.playlist(id: "p1")
        XCTAssertNil(playlist?.lastSyncedAt)
    }

    func test_authenticationFailureStopsSync() async throws {
        // Kimlik doğrulama başarısızsa devam etmenin anlamı yok.
        let provider = FakeProvider(channels: [], authError: AppError.unauthorized)

        do {
            try await makeService(provider).sync(playlistID: "p1")
            XCTFail("Kimlik doğrulama hatası senkronizasyonu durdurmalı")
        } catch {
            XCTAssertEqual(error as? AppError, .unauthorized)
        }
    }

    func test_guideStorageFailureDoesNotMarkCatalogSyncSuccessful() async throws {
        try await database.write { db in
            try db.execute(sql: """
                CREATE TRIGGER rejectGuideWrite BEFORE INSERT ON epgProgram
                BEGIN SELECT RAISE(ABORT, 'guide storage failure'); END
                """)
        }
        let provider = SampleLibraryContentProvider(playlistID: "p1")
        do {
            try await makeService(provider).sync(playlistID: "p1")
            XCTFail("Rehber kayıt arızası isteğe bağlı ağ hatası sayılamaz")
        } catch {
            guard case .storage = error as? AppError else {
                return XCTFail("Depo hatası bekleniyordu")
            }
        }
        let playlist = try await playlists.playlist(id: "p1")
        XCTAssertNil(playlist?.lastSyncedAt)
    }

    // MARK: - İlerleme yayını

    func test_progressStreamReportsStagesAndFinishes() async throws {
        let provider = FakeProvider(channels: [makeChannel(id: "1", name: "K")])
        let service = makeService(provider)

        let stream = service.observeProgress(playlistID: "p1")
        var iterator = stream.makeAsyncIterator()

        // Yeni abone mevcut durumu hemen görmeli.
        let initial = await iterator.next()
        XCTAssertEqual(initial, .idle)

        try await service.sync(playlistID: "p1")

        var sawFinished = false
        var finishedCounts: SyncContentCounts?
        for _ in 0..<10 {
            guard let stage = await iterator.next() else { break }
            if case .finished(_, let counts) = stage {
                sawFinished = true
                finishedCounts = counts
                break
            }
        }
        XCTAssertTrue(sawFinished, "Senkronizasyon bitişi yayınlanmalı")
        XCTAssertEqual(finishedCounts?.channels, 1)
        XCTAssertEqual(finishedCounts?.movies, 0)
        XCTAssertEqual(finishedCounts?.series, 0)
    }

    func test_failureIsPublishedToObservers() async throws {
        let provider = FakeProvider(channels: [], authError: AppError.unauthorized)
        let service = makeService(provider)

        let stream = service.observeProgress(playlistID: "p1")
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()   // .idle

        _ = try? await service.sync(playlistID: "p1")

        var sawFailure = false
        for _ in 0..<10 {
            guard let stage = await iterator.next() else { break }
            if case .failed = stage { sawFailure = true; break }
        }
        XCTAssertTrue(sawFailure, "Hata ekrana yansıtılmalı")
    }

    // MARK: - Eşzamanlılık

    func test_concurrentSyncsShareSingleRun() async throws {
        // Kullanıcı iki kez "yenile" derse iki tam senkronizasyon başlamamalı.
        let provider = FakeProvider(channels: [makeChannel(id: "1", name: "K")])
        let service = makeService(provider)

        async let first: Void = service.sync(playlistID: "p1")
        async let second: Void = service.sync(playlistID: "p1")
        _ = try await (first, second)

        let authCount = await provider.authenticateCount
        XCTAssertEqual(authCount, 1, "Eşzamanlı çağrılar aynı işi paylaşmalı")
    }

    func test_accountRefreshDoesNotUndoSourceSelectionOrEditsMadeDuringAuthentication() async throws {
        try await playlists.add(
            Playlist(id: "p2", name: "İkinci", kind: .m3u(url: URL(string: "https://list.example.com/second.m3u")!), createdAt: Date()),
            password: nil
        )
        let started = expectation(description: "Doğrulama başladı")
        let gate = SyncTestGate(started: started)
        let expiration = Date(timeIntervalSince1970: 2_000_000_000)
        let provider = FakeProvider(
            channels: [makeChannel(id: "1", name: "Kanal")],
            accountExpiration: expiration,
            beforeAuthenticate: { await gate.wait() }
        )
        let service = makeService(provider)
        let request = Task { try await service.sync(playlistID: "p1") }
        await fulfillment(of: [started], timeout: 2)

        try await playlists.setActive(id: "p2")
        let fetched = try await playlists.playlist(id: "p1")
        var edited = try XCTUnwrap(fetched)
        edited.name = "Yeni ad"
        try await playlists.update(edited)
        await gate.open()
        try await request.value

        let all = try await playlists.all()
        XCTAssertEqual(all.filter(\.isActive).map(\.id), ["p2"])
        let updated = try await playlists.playlist(id: "p1")
        XCTAssertEqual(updated?.name, "Yeni ad")
        XCTAssertEqual(updated?.expiresAt, expiration)
    }

    func test_sourceCancellationStopsSharedSyncBeforeWritingCatalog() async throws {
        let started = expectation(description: "Doğrulama başladı")
        let gate = SyncTestGate(started: started)
        let provider = FakeProvider(
            channels: [makeChannel(id: "1", name: "Kanal")],
            beforeAuthenticate: { await gate.wait() }
        )
        let service = makeService(provider)
        let request = Task { try await service.sync(playlistID: "p1") }
        await fulfillment(of: [started], timeout: 2)

        await service.cancel(playlistID: "p1")
        await gate.open()

        do {
            try await request.value
            XCTFail("Bırakılan kaynağın ortak işi sürmemeli")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let stored = try await channels.channels(playlistID: "p1", categoryID: nil)
        let playlist = try await playlists.playlist(id: "p1")
        XCTAssertTrue(stored.isEmpty)
        XCTAssertNil(playlist?.lastSyncedAt)

        try await service.sync(playlistID: "p1")
        let reloaded = try await channels.channels(playlistID: "p1", categoryID: nil)
        XCTAssertEqual(reloaded.count, 1, "Sonraki çağrı eski iptal edilmiş işi paylaşmamalı")
    }

    // MARK: - Test yardımcıları

    /// - Parameter sortOrder: Sağlayıcının verdiği liste sırası.
    ///   Belirtilmezse tüm kanallar aynı sıraya düşer ve depo ada göre
    ///   sıralar — bu doğru davranıştır, ama testin sırayı ada göre
    ///   beklemesi gerekir. Karışıklık olmasın diye açıkça veriliyor.
    private func makeChannel(id: String, name: String, sortOrder: Int = 0) -> Channel {
        Channel(
            id: EntityID.channel(playlistID: "p1", rawID: id),
            playlistID: "p1",
            name: name,
            streamKey: id,
            sortOrder: sortOrder
        )
    }

    private func makeCategory(id: String, name: String) -> MediaCategory {
        MediaCategory(
            id: EntityID.category(playlistID: "p1", kind: .live, rawID: id),
            playlistID: "p1",
            kind: .live,
            name: name
        )
    }
}

// MARK: - Sahte sağlayıcı

actor FakeProvider: ContentProvider {

    private var channels: [Channel]
    private let liveCategories: [MediaCategory]
    private let authError: Error?
    private let liveError: Error?
    private let channelError: Error?
    private let movies: [Movie]
    private let movieError: Error?
    private let series: [Series]
    private let seriesError: Error?
    /// `nonisolated` erişim için `let`: sağlayıcı kurulduktan sonra değişmez.
    private let epgURL: URL?
    private let accountExpiration: Date?
    private let beforeAuthenticate: (@Sendable () async -> Void)?

    private(set) var authenticateCount = 0

    init(
        channels: [Channel],
        liveCategories: [MediaCategory] = [],
        authError: Error? = nil,
        liveError: Error? = nil,
        channelError: Error? = nil,
        movies: [Movie] = [],
        movieError: Error? = nil,
        series: [Series] = [],
        seriesError: Error? = nil,
        epgURL: URL? = nil,
        accountExpiration: Date? = nil,
        beforeAuthenticate: (@Sendable () async -> Void)? = nil
    ) {
        self.channels = channels
        self.liveCategories = liveCategories
        self.authError = authError
        self.liveError = liveError
        self.channelError = channelError
        self.movies = movies
        self.movieError = movieError
        self.series = series
        self.seriesError = seriesError
        self.epgURL = epgURL
        self.accountExpiration = accountExpiration
        self.beforeAuthenticate = beforeAuthenticate
    }

    func setChannels(_ newChannels: [Channel]) {
        channels = newChannels
    }

    nonisolated var streamHeaders: [String: String] { [:] }

    func authenticate() async throws -> ProviderAccount {
        authenticateCount += 1
        await beforeAuthenticate?()
        if let authError { throw authError }
        return ProviderAccount(
            username: "u", expiresAt: accountExpiration, isTrial: false,
            maxConnections: 1, activeConnections: 0
        )
    }

    func fetchCategories(kind: MediaCategory.Kind) async throws -> [MediaCategory] {
        switch kind {
        case .live: if let liveError { throw liveError }; return liveCategories
        case .movie: if let movieError { throw movieError }; return []
        case .series: if let seriesError { throw seriesError }; return []
        }
    }

    func fetchChannels(categoryID: MediaCategory.ID?) async throws -> [Channel] {
        if let channelError { throw channelError }
        return channels
    }

    func fetchMovies(categoryID: MediaCategory.ID?) async throws -> [Movie] {
        if let movieError { throw movieError }
        return movies
    }

    func fetchSeries(categoryID: MediaCategory.ID?) async throws -> [Series] {
        if let seriesError { throw seriesError }
        return series
    }

    func fetchMovieDetails(streamKey: String) async throws -> Movie { throw AppError.notFound }

    func fetchSeriesDetails(
        streamKey: String
    ) async throws -> (seasons: [Season], episodes: [Episode]) {
        throw AppError.notFound
    }

    nonisolated var epgSourceURL: URL? { epgURL }

    nonisolated func streamURL(for channel: Channel) -> URL? { URL(string: channel.streamKey) }
    nonisolated func streamURL(for movie: Movie) -> URL? { nil }
    nonisolated func streamURL(for episode: Episode) -> URL? { nil }
}

struct FakeProviderFactory: ContentProviderFactory {
    let provider: ContentProvider

    func makeProvider(for playlist: Playlist) async throws -> ContentProvider { provider }
}

actor SyncTestGate {
    private let started: XCTestExpectation
    private let duplicate: XCTestExpectation?
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var calls = 0
    var isClosed: Bool { !isOpen }

    init(started: XCTestExpectation, duplicate: XCTestExpectation? = nil) {
        self.started = started
        self.duplicate = duplicate
    }

    func wait() async {
        calls += 1
        if calls == 1 { started.fulfill() }
        if calls > 1 { duplicate?.fulfill() }
        if !isOpen { await withCheckedContinuation { waiters.append($0) } }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}
