import XCTest
import GRDB
import OctopusDomain
@testable import OctopusData

/// Şema ve göç testleri.
///
/// Bellek içi veritabanı kullanır — diske dokunmaz, paralel koşabilir.
final class DatabaseSchemaTests: XCTestCase {

    private func makeDatabase() throws -> AppDatabase {
        try AppDatabase.makeInMemory()
    }

    // MARK: - Göç

    func test_migration_createsEveryTable() async throws {
        let appDatabase = try makeDatabase()

        let expected = [
            "playlist", "category", "channel", "movie",
            "series", "season", "episode", "epgProgram",
            "favorite", "playbackProgress", "watchHistory"
        ]

        for table in expected {
            let exists = try await appDatabase.read { db in
                try db.tableExists(table)
            }
            XCTAssertTrue(exists, "'\(table)' tablosu oluşturulmamış")
        }
    }

    func test_migration_isIdempotent() async throws {
        // Aynı bağlantıda ikinci kez göç uygulanması hata vermemeli.
        let queue = try DatabaseQueue(configuration: AppDatabase.makeConfiguration())
        _ = try AppDatabase(queue)
        XCTAssertNoThrow(try AppDatabase(queue), "Göç zinciri tekrar uygulanabilir olmalı")
    }

    // MARK: - Yabancı anahtar / cascade
    //
    // Kaynak silinince ona ait TÜM içerik gitmeli; yetim satır kalmamalı.

    func test_deletingPlaylist_cascadesToContent() async throws {
        let appDatabase = try makeDatabase()

        try await appDatabase.write { db in
            try db.execute(
                sql: """
                    INSERT INTO playlist (id, name, kindType, createdAt, isActive)
                    VALUES ('p1', 'Test', 'm3u', '2026-01-01 00:00:00', 1)
                    """
            )
            try db.execute(
                sql: """
                    INSERT INTO channel (id, playlistId, name, streamKey, sortOrder, isAdult)
                    VALUES ('p1#live#1', 'p1', 'TRT 1', '1', 0, 0)
                    """
            )
        }

        let beforeCount = try await appDatabase.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM channel") ?? 0
        }
        XCTAssertEqual(beforeCount, 1)

        try await appDatabase.write { db in
            try db.execute(sql: "DELETE FROM playlist WHERE id = 'p1'")
        }

        let afterCount = try await appDatabase.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM channel") ?? 0
        }
        XCTAssertEqual(afterCount, 0, "Yabancı anahtar cascade çalışmıyor")
    }

    func test_userData_survivesPlaylistDeletion() async throws {
        // Favoriler kaynağa bağlı DEĞİL: kullanıcı kaynağı silip yeniden
        // eklediğinde favorileri kaybolmamalı.
        let appDatabase = try makeDatabase()

        try await appDatabase.write { db in
            try db.execute(
                sql: """
                    INSERT INTO playlist (id, name, kindType, createdAt, isActive)
                    VALUES ('p1', 'Test', 'm3u', '2026-01-01 00:00:00', 1)
                    """
            )
            try db.execute(
                sql: """
                    INSERT INTO favorite (itemKey, addedAt)
                    VALUES ('live:p1#live#1', '2026-01-01 00:00:00')
                    """
            )
            try db.execute(sql: "DELETE FROM playlist WHERE id = 'p1'")
        }

        let favoriteCount = try await appDatabase.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM favorite") ?? 0
        }
        XCTAssertEqual(favoriteCount, 1, "Favoriler kaynak silinince kaybolmamalı")
    }

    // MARK: - Tam metin arama

    func test_ftsIndex_staysInSyncWithChannelTable() async throws {
        let appDatabase = try makeDatabase()

        try await appDatabase.write { db in
            try db.execute(
                sql: """
                    INSERT INTO playlist (id, name, kindType, createdAt, isActive)
                    VALUES ('p1', 'Test', 'm3u', '2026-01-01 00:00:00', 1)
                    """
            )
            try db.execute(
                sql: """
                    INSERT INTO channel (id, playlistId, name, streamKey, sortOrder, isAdult)
                    VALUES ('p1#live#1', 'p1', 'Spor Kanalı', '1', 0, 0)
                    """
            )
        }

        // Ekleme trigger'ı: arama indeksinde görünmeli.
        let found = try await appDatabase.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT channel.name FROM channel
                    JOIN channelSearch ON channelSearch.rowid = channel.rowid
                    WHERE channelSearch MATCH ?
                    """,
                arguments: ["Spor"]
            )
        }
        XCTAssertEqual(found, ["Spor Kanalı"], "FTS indeksi eklemeyi yakalamadı")

        // Silme trigger'ı: indeksten de düşmeli.
        try await appDatabase.write { db in
            try db.execute(sql: "DELETE FROM channel WHERE id = 'p1#live#1'")
        }

        let afterDelete = try await appDatabase.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM channelSearch WHERE channelSearch MATCH ?",
                arguments: ["Spor"]
            ) ?? 0
        }
        XCTAssertEqual(afterDelete, 0, "FTS indeksi silmeyi yakalamadı")
    }

    // MARK: - Kimlik kurulumu

    func test_entityID_disambiguatesAcrossPlaylists() {
        // Aynı ham id, iki farklı kaynakta → farklı kimlik üretmeli.
        let first = EntityID.channel(playlistID: "p1", rawID: "1234")
        let second = EntityID.channel(playlistID: "p2", rawID: "1234")
        XCTAssertNotEqual(first, second, "Kaynaklar arası kimlik çakışması var")
    }

    func test_entityID_disambiguatesAcrossContentKinds() {
        // Xtream'de canlı ve VOD id'leri çakışabilir.
        let channel = EntityID.channel(playlistID: "p1", rawID: "1234")
        let movie = EntityID.movie(playlistID: "p1", rawID: "1234")
        XCTAssertNotEqual(channel.value, movie.value)
    }

    func test_entityID_escapesSeparatorInRawValue() {
        // Ham değerde ayraç geçerse kimlik bozulmamalı.
        let id = EntityID.channel(playlistID: "p1", rawID: "12#34")
        XCTAssertEqual(id.value, "p1#live#12_34")
    }

    func test_entityID_categoryIsScopedByKind() {
        let live = EntityID.category(playlistID: "p1", kind: .live, rawID: "5")
        let movie = EntityID.category(playlistID: "p1", kind: .movie, rawID: "5")
        XCTAssertNotEqual(live, movie)
    }
}
