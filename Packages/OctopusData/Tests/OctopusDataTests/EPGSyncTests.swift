import XCTest
import OctopusDomain
@testable import OctopusData

/// EPG senkronizasyonu: iki kapı (kapsam ve kısıtlama) ve akış halinde yazma.
final class EPGSyncTests: XCTestCase {

    private var database: AppDatabase!
    private var playlists: GRDBPlaylistRepository!
    private var epg: GRDBEPGRepository!
    private var store: UserDefaults!
    private let suiteName = "epg.sync.tests"

    /// Testlerde sabit "şimdi": 2026-08-05 12:00 UTC
    private let now = Date(timeIntervalSince1970: 1_785_931_200)

    override func setUp() async throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
        store = UserDefaults(suiteName: suiteName)

        database = try AppDatabase.makeInMemory()
        playlists = GRDBPlaylistRepository(database: database, secrets: FakeSecretStore())
        epg = GRDBEPGRepository(database: database)

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

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// Verilen saat aralığında tek programlı XMLTV.
    private func guideXML(startOffsetHours: Int, durationHours: Int = 2) -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMddHHmmss"

        let start = now.addingTimeInterval(Double(startOffsetHours) * 3_600)
        let stop = start.addingTimeInterval(Double(durationHours) * 3_600)

        return Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <tv>
              <programme start="\(formatter.string(from: start))" \
            stop="\(formatter.string(from: stop))" channel="trt1">
                <title>Haberler</title>
              </programme>
            </tv>
            """.utf8)
    }

    private func makeService(
        epgURL: URL? = URL(string: "http://epg.example.com/guide.xml"),
        requestLog: LockedBox<Int>? = nil,
        body: @escaping @Sendable () throws -> Data
    ) -> ContentSyncService {
        ContentSyncService(
            playlists: playlists,
            providerFactory: FakeProviderFactory(
                provider: FakeProvider(channels: [], epgURL: epgURL)
            ),
            database: database,
            httpClient: StubHTTPClient { _ in
                if let requestLog { requestLog.set(requestLog.get() + 1) }
                return try body()
            },
            store: store,
            now: { self.now }
        )
    }

    // MARK: - Temel akış

    func test_guideIsDownloadedAndStored() async throws {
        let service = makeService { self.guideXML(startOffsetHours: 0) }
        try await service.syncEPG(playlistID: "p1")

        let program = try await epg.nowPlaying(
            epgChannelID: "trt1",
            at: now.addingTimeInterval(600)
        )
        XCTAssertEqual(program?.title, "Haberler")
    }

    func test_sourceWithoutGuideIsSkippedSilently() async throws {
        // Kaynak rehber sunmuyorsa bu bir hata değil.
        let log = LockedBox(0)
        let service = makeService(epgURL: nil, requestLog: log) { Data() }

        try await service.syncEPG(playlistID: "p1")
        XCTAssertEqual(log.get(), 0, "Adres yokken istek atılmamalı")
    }

    // MARK: - Kapsam kapısı

    func test_freshGuideIsNotDownloadedAgain() async throws {
        // Rehber ileriyi kapsıyorsa yüzlerce megabaytı yeniden indirmek anlamsız.
        let log = LockedBox(0)
        let service = makeService(requestLog: log) {
            self.guideXML(startOffsetHours: 0, durationHours: 10)
        }

        try await service.syncEPG(playlistID: "p1")
        XCTAssertEqual(log.get(), 1)

        // Kısıtlama penceresini aşan ama kapsamı hâlâ geçerli bir servis.
        let later = ContentSyncService(
            playlists: playlists,
            providerFactory: FakeProviderFactory(
                provider: FakeProvider(
                    channels: [],
                    epgURL: URL(string: "http://epg.example.com/guide.xml")
                )
            ),
            database: database,
            httpClient: StubHTTPClient { _ in
                log.set(log.get() + 1)
                return self.guideXML(startOffsetHours: 0)
            },
            store: store,
            // 7 saat sonra: kısıtlama penceresi doldu ama rehber hâlâ geçerli.
            now: { self.now.addingTimeInterval(7 * 3_600) }
        )
        try await later.syncEPG(playlistID: "p1")

        XCTAssertEqual(log.get(), 1, "Kapsam geçerliyken yeniden indirilmemeli")
    }

    func test_expiringGuideIsRefreshed() async throws {
        // Rehber yalnızca 1 saat ileriyi kapsıyorsa tazelenmeli.
        let log = LockedBox(0)
        let service = makeService(requestLog: log) {
            self.guideXML(startOffsetHours: 0, durationHours: 1)
        }
        try await service.syncEPG(playlistID: "p1")

        let later = ContentSyncService(
            playlists: playlists,
            providerFactory: FakeProviderFactory(
                provider: FakeProvider(
                    channels: [],
                    epgURL: URL(string: "http://epg.example.com/guide.xml")
                )
            ),
            database: database,
            httpClient: StubHTTPClient { _ in
                log.set(log.get() + 1)
                return self.guideXML(startOffsetHours: 7, durationHours: 4)
            },
            store: store,
            now: { self.now.addingTimeInterval(7 * 3_600) }
        )
        try await later.syncEPG(playlistID: "p1")

        XCTAssertEqual(log.get(), 2, "Kapsam bitince yeniden indirilmeli")
    }

    // MARK: - Kısıtlama kapısı

    func test_retryWithinSixHoursIsThrottled() async throws {
        // Kopuk sunucuda her açılışta yüzlerce megabayt denemesi yapılmamalı.
        let log = LockedBox(0)
        let service = makeService(requestLog: log) {
            throw AppError.network(reason: "kopuk")
        }

        _ = try? await service.syncEPG(playlistID: "p1")
        XCTAssertEqual(log.get(), 1)

        // Aynı "şimdi" ile ikinci deneme — kısıtlama devrede.
        _ = try? await service.syncEPG(playlistID: "p1")
        XCTAssertEqual(log.get(), 1, "Başarısız deneme de kısıtlamaya sayılmalı")
    }

    // MARK: - Temizlik

    func test_expiredProgramsArePurged() async throws {
        // Önce çok eski bir program yazılır.
        try await database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO epgProgram (id, epgChannelId, title, startDate, endDate)
                    VALUES ('eski', 'trt1', 'Çok Eski', '2020-01-01 00:00:00', '2020-01-01 01:00:00')
                    """
            )
        }

        let service = makeService { self.guideXML(startOffsetHours: 0) }
        try await service.syncEPG(playlistID: "p1")

        let remaining = try await database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM epgProgram WHERE id = 'eski'") ?? 0
        }
        XCTAssertEqual(remaining, 0, "Süresi geçmiş programlar temizlenmeli")
    }

    func test_recentlyEndedProgramsAreKept() async throws {
        // "Az önce ne oynadı" bilgisi korunmalı; 6 saat pay bırakılıyor.
        let service = makeService { self.guideXML(startOffsetHours: -2, durationHours: 1) }
        try await service.syncEPG(playlistID: "p1")

        let count = try await database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM epgProgram") ?? 0
        }
        XCTAssertEqual(count, 1, "Yeni biten program silinmemeli")
    }

    // MARK: - Katalog senkronizasyonuyla ilişki

    func test_guideFailureDoesNotFailCatalogSync() async throws {
        // Rehber alınamazsa katalog yine de kullanılabilir olmalı.
        let service = makeService { throw AppError.network(reason: "kopuk") }
        try await service.sync(playlistID: "p1")

        let playlist = try await playlists.playlist(id: "p1")
        XCTAssertNotNil(playlist?.lastSyncedAt, "Katalog senkronizasyonu tamamlanmış olmalı")
    }
}
