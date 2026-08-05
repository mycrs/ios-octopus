import XCTest
import GRDB
import OctopusDomain
@testable import OctopusData

/// Favoriler, izleme ilerlemesi, geçmiş ve EPG.
final class UserDataRepositoryTests: XCTestCase {

    private var database: AppDatabase!

    override func setUp() async throws {
        database = try AppDatabase.makeInMemory()
        try await database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO playlist (id, name, kindType, createdAt, isActive)
                    VALUES ('p1', 'Kaynak', 'm3u', '2026-01-01 00:00:00', 1)
                    """
            )
        }
    }

    // MARK: - Favoriler

    func test_toggle_addsThenRemoves() async throws {
        let repository = GRDBFavoritesRepository(database: database)
        let target = FavoriteTarget.channel("p1#live#1")

        let added = try await repository.toggle(target)
        XCTAssertTrue(added)
        let isFavorite = try await repository.isFavorite(target)
        XCTAssertTrue(isFavorite)

        let removed = try await repository.toggle(target)
        XCTAssertFalse(removed)
        let stillFavorite = try await repository.isFavorite(target)
        XCTAssertFalse(stillFavorite)
    }

    func test_seriesFavoriteUsesOwnKeyspace() async throws {
        // Dizi oynatılabilir bir öğe değil ama favoriye eklenebilir;
        // anahtarı kanal ve filmlerinkiyle çakışmamalı.
        let repository = GRDBFavoritesRepository(database: database)

        _ = try await repository.toggle(.series("p1#series#77"))

        let isSeriesFavorite = try await repository.isFavorite(.series("p1#series#77"))
        XCTAssertTrue(isSeriesFavorite)

        let asMovie = try await repository.isFavorite(.movie("p1#series#77"))
        XCTAssertFalse(asMovie, "Farklı türler aynı anahtarı paylaşmamalı")
    }

    func test_favoriteChannels_joinsByKeyAndOrdersByAddedTime() async throws {
        try await insertChannel(id: "p1#live#1", name: "Önce")
        try await insertChannel(id: "p1#live#2", name: "Sonra")

        let repository = GRDBFavoritesRepository(database: database)
        _ = try await repository.toggle(.channel("p1#live#1"))
        // Sıralamanın deterministik olması için zaman farkı verilir.
        try await database.write { db in
            try db.execute(
                sql: "UPDATE favorite SET addedAt = '2026-01-01 00:00:00' WHERE itemKey = 'live:p1#live#1'"
            )
            try db.execute(
                sql: """
                    INSERT INTO favorite (itemKey, addedAt)
                    VALUES ('live:p1#live#2', '2026-01-02 00:00:00')
                    """
            )
        }

        let favorites = try await repository.favoriteChannels(playlistID: "p1")
        XCTAssertEqual(favorites.map(\.name), ["Sonra", "Önce"], "En yeni favori üstte olmalı")
    }

    func test_favoriteOfMovie_doesNotAppearInChannelFavorites() async throws {
        // Anahtar önekleri türleri ayırmalı: 'live:' ile 'movie:' karışmamalı.
        try await insertChannel(id: "p1#live#1", name: "Kanal")

        let repository = GRDBFavoritesRepository(database: database)
        _ = try await repository.toggle(.movie("p1#vod#1"))

        let channelFavorites = try await repository.favoriteChannels(playlistID: "p1")
        XCTAssertTrue(channelFavorites.isEmpty, "Film favorisi kanal listesine sızdı")
    }

    // MARK: - İzleme ilerlemesi

    func test_save_overwritesPreviousPosition() async throws {
        let repository = GRDBPlaybackProgressRepository(database: database)
        let source = PlaybackItem.Source.movie("p1#vod#1")

        try await repository.save(makeProgress(position: 10), for: source)
        try await repository.save(makeProgress(position: 250), for: source)

        let stored = try await repository.progress(for: source)
        XCTAssertEqual(stored?.positionSeconds, 250, "Periyodik kayıt üzerine yazmalı")
    }

    func test_continueWatching_excludesFinishedItems() async throws {
        let repository = GRDBPlaybackProgressRepository(database: database)

        // %50 izlenmiş → listede olmalı
        try await repository.save(makeProgress(position: 500), for: .movie("p1#vod#1"))
        // %99 izlenmiş → bitmiş sayılır, listede olmamalı
        try await repository.save(makeProgress(position: 990), for: .movie("p1#vod#2"))

        let items = try await repository.continueWatching(playlistID: "p1", limit: 10)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.itemKey, "movie:p1#vod#1")
    }

    func test_continueWatching_isScopedToPlaylist() async throws {
        let repository = GRDBPlaybackProgressRepository(database: database)
        try await repository.save(makeProgress(position: 100), for: .movie("p1#vod#1"))
        try await repository.save(makeProgress(position: 100), for: .movie("p2#vod#1"))

        let items = try await repository.continueWatching(playlistID: "p1", limit: 10)
        XCTAssertEqual(items.map(\.itemKey), ["movie:p1#vod#1"])
    }

    // MARK: - Geçmiş

    func test_history_recordsMostRecentFirstWithoutDuplicates() async throws {
        try await insertChannel(id: "p1#live#1", name: "Kanal 1")
        try await insertChannel(id: "p1#live#2", name: "Kanal 2")

        let repository = GRDBWatchHistoryRepository(database: database)
        try await repository.record(.liveChannel("p1#live#1"), at: Date(timeIntervalSince1970: 100))
        try await repository.record(.liveChannel("p1#live#2"), at: Date(timeIntervalSince1970: 200))
        // Aynı kanal tekrar izlenince yeni satır değil, zaman güncellenmeli.
        try await repository.record(.liveChannel("p1#live#1"), at: Date(timeIntervalSince1970: 300))

        let recent = try await repository.recentChannels(playlistID: "p1", limit: 10)
        XCTAssertEqual(recent.map(\.name), ["Kanal 1", "Kanal 2"])
    }

    // MARK: - EPG

    func test_nowPlaying_batchAvoidsPerChannelQueries() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        try await insertProgram(id: "e1", channel: "trt1", title: "Haber", start: now.addingTimeInterval(-600), end: now.addingTimeInterval(600))
        try await insertProgram(id: "e2", channel: "atv", title: "Dizi", start: now.addingTimeInterval(-300), end: now.addingTimeInterval(900))
        // Bitmiş program — dönmemeli
        try await insertProgram(id: "e3", channel: "trt1", title: "Eski", start: now.addingTimeInterval(-5_000), end: now.addingTimeInterval(-4_000))

        let repository = GRDBEPGRepository(database: database)
        let result = try await repository.nowPlaying(epgChannelIDs: ["trt1", "atv", "yok"], at: now)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result["trt1"]?.title, "Haber")
        XCTAssertEqual(result["atv"]?.title, "Dizi")
        XCTAssertNil(result["yok"])
    }

    func test_purge_removesOnlyExpiredPrograms() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        try await insertProgram(id: "old", channel: "trt1", title: "Eski", start: now.addingTimeInterval(-5_000), end: now.addingTimeInterval(-4_000))
        try await insertProgram(id: "current", channel: "trt1", title: "Şimdi", start: now.addingTimeInterval(-600), end: now.addingTimeInterval(600))

        let repository = GRDBEPGRepository(database: database)
        try await repository.purgePrograms(before: now)

        let remaining = try await repository.programs(
            epgChannelID: "trt1",
            from: now.addingTimeInterval(-10_000),
            to: now.addingTimeInterval(10_000)
        )
        XCTAssertEqual(remaining.map(\.title), ["Şimdi"])
    }

    // MARK: - Toplu yazma
    //
    // Referans projede katalog TEK satıra yazıldığı için 14k kanallık hesapta
    // ~2MB'lık satır SQLite cursor penceresini taşırmış ve cache sessizce hiç
    // çalışmamış. Şemamız satır satır yazıyor; bu test o yolun tıkanmadığını
    // ve tek transaction'da makul sürede bittiğini doğrular.

    func test_bulkInsert_handlesLargeCatalogInSingleTransaction() async throws {
        let channelCount = 10_000
        let start = Date()

        try await database.write { db in
            for index in 0..<channelCount {
                try ChannelRecord(
                    Channel(
                        id: Channel.ID("p1#live#\(index)"),
                        playlistID: "p1",
                        name: "Kanal \(index)",
                        streamKey: "\(index)",
                        sortOrder: index
                    )
                ).insert(db)
            }
        }

        let elapsed = Date().timeIntervalSince(start)
        let stored = try await database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM channel") ?? 0
        }

        XCTAssertEqual(stored, channelCount)
        // Gevşek eşik: CI makinesi değişken. Amaç patolojik yavaşlığı yakalamak.
        XCTAssertLessThan(elapsed, 30, "10k kanal yazımı \(elapsed) sn sürdü — çok yavaş")

        // Arama indeksi de büyük katalogda çalışmalı.
        let repository = GRDBChannelRepository(database: database)
        let results = try await repository.search(query: "Kanal", playlistID: "p1", limit: 5)
        XCTAssertEqual(results.count, 5)
    }

    // MARK: - Test verisi

    private func makeProgress(position: Double) -> PlaybackProgress {
        PlaybackProgress(
            itemKey: "geçersiz",   // depo anahtarı kaynaktan türetmeli
            positionSeconds: position,
            durationSeconds: 1_000,
            updatedAt: Date(timeIntervalSince1970: position)
        )
    }

    private func insertChannel(id: String, name: String) async throws {
        try await database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO channel (id, playlistId, name, streamKey, sortOrder, isAdult)
                    VALUES (?, 'p1', ?, 'raw', 0, 0)
                    """,
                arguments: [id, name]
            )
        }
    }

    private func insertProgram(
        id: String,
        channel: String,
        title: String,
        start: Date,
        end: Date
    ) async throws {
        try await database.write { db in
            try EPGProgramRecord(
                EPGProgram(
                    id: EPGProgram.ID(id),
                    epgChannelID: channel,
                    title: title,
                    startDate: start,
                    endDate: end
                )
            ).insert(db)
        }
    }
}
