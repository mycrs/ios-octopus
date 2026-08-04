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

    private func makeService(_ provider: FakeProvider) -> ContentSyncService {
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
        _ = try await favorites.toggle(.liveChannel(channelID))

        try await service.sync(playlistID: "p1")

        let isFavorite = try await favorites.isFavorite(.liveChannel(channelID))
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
        for _ in 0..<10 {
            guard let stage = await iterator.next() else { break }
            if case .finished = stage { sawFinished = true; break }
        }
        XCTAssertTrue(sawFinished, "Senkronizasyon bitişi yayınlanmalı")
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
    private let movieError: Error?
    private let seriesError: Error?

    private(set) var authenticateCount = 0

    init(
        channels: [Channel],
        liveCategories: [MediaCategory] = [],
        authError: Error? = nil,
        movieError: Error? = nil,
        seriesError: Error? = nil
    ) {
        self.channels = channels
        self.liveCategories = liveCategories
        self.authError = authError
        self.movieError = movieError
        self.seriesError = seriesError
    }

    func setChannels(_ newChannels: [Channel]) {
        channels = newChannels
    }

    nonisolated var streamHeaders: [String: String] { [:] }

    func authenticate() async throws -> ProviderAccount {
        authenticateCount += 1
        if let authError { throw authError }
        return ProviderAccount(
            username: "u", expiresAt: nil, isTrial: false,
            maxConnections: 1, activeConnections: 0
        )
    }

    func fetchCategories(kind: MediaCategory.Kind) async throws -> [MediaCategory] {
        switch kind {
        case .live: return liveCategories
        case .movie: if let movieError { throw movieError }; return []
        case .series: if let seriesError { throw seriesError }; return []
        }
    }

    func fetchChannels(categoryID: MediaCategory.ID?) async throws -> [Channel] { channels }

    func fetchMovies(categoryID: MediaCategory.ID?) async throws -> [Movie] {
        if let movieError { throw movieError }
        return []
    }

    func fetchSeries(categoryID: MediaCategory.ID?) async throws -> [Series] {
        if let seriesError { throw seriesError }
        return []
    }

    func fetchMovieDetails(streamKey: String) async throws -> Movie { throw AppError.notFound }

    func fetchSeriesDetails(
        streamKey: String
    ) async throws -> (seasons: [Season], episodes: [Episode]) {
        throw AppError.notFound
    }

    func fetchEPG() async throws -> [EPGProgram] { [] }

    nonisolated func streamURL(for channel: Channel) -> URL? { URL(string: channel.streamKey) }
    nonisolated func streamURL(for movie: Movie) -> URL? { nil }
    nonisolated func streamURL(for episode: Episode) -> URL? { nil }
}

struct FakeProviderFactory: ContentProviderFactory {
    let provider: ContentProvider

    func makeProvider(for playlist: Playlist) async throws -> ContentProvider { provider }
}
