import XCTest
import GRDB
import OctopusDomain
@testable import OctopusData

final class SourceHealthReaderTests: XCTestCase {
    func test_summaryIsScopedToOneSourceAndIgnoresEmptyDuplicateKeys() async throws {
        let database = try AppDatabase.makeInMemory()
        let date = Date(timeIntervalSince1970: 1_000)
        try await database.write { db in
            try db.execute(sql: """
                INSERT INTO playlist (id, name, kindType, createdAt, isActive)
                VALUES ('p1', 'Private name', 'm3u', '2026-01-01 00:00:00', 1), ('p2', 'Other', 'm3u', '2026-01-01 00:00:00', 0);
                INSERT INTO channel (id, playlistId, name, streamKey, epgChannelId, logoURL) VALUES
                ('c1', 'p1', 'A', 'same', 'guide', 'https://x/logo'),
                ('c2', 'p1', 'B', ' same ', NULL, NULL),
                ('c3', 'p1', 'C', '', ' ', ''),
                ('c4', 'p1', 'D', ' ', NULL, ' '),
                ('c5', 'p2', 'E', 'same', NULL, NULL);
                """)
            try MovieRecord(Movie(id: "m1", playlistID: "p1", title: "Movie", streamKey: "1")).insert(db)
            try SeriesRecord(Series(id: "s1", playlistID: "p1", title: "Series", streamKey: "1")).insert(db)
            try CategoryRecord(MediaCategory(id: "cat", playlistID: "p1", kind: .live, name: "Group")).insert(db)
        }

        let summary = try await GRDBSourceHealthReader(database: database).snapshot(playlistID: "p1", at: date)

        XCTAssertEqual(summary.channels, 4)
        XCTAssertEqual(summary.movies, 1)
        XCTAssertEqual(summary.series, 1)
        XCTAssertEqual(summary.categories, 1)
        XCTAssertEqual(summary.duplicateChannels, 1)
        XCTAssertEqual(summary.channelsWithoutGuide, 3)
        XCTAssertEqual(summary.channelsWithoutArtwork, 3)
        XCTAssertEqual(summary.checkedAt, date)
    }

    func test_emptySourceHasZeroCountsAndExpiryUsesProvidedClock() async throws {
        let database = try AppDatabase.makeInMemory()
        let date = Date(timeIntervalSince1970: 1_000)
        try await database.write { db in
            try db.execute(sql: """
                INSERT INTO playlist (id, name, kindType, createdAt, isActive, expiresAt)
                VALUES ('p1', 'Account', 'xtream', '2026-01-01 00:00:00', 1, ?)
                """, arguments: [date])
        }
        let reader = GRDBSourceHealthReader(database: database)
        let expired = try await reader.snapshot(playlistID: "p1", at: date)
        let valid = try await reader.snapshot(playlistID: "p1", at: date.addingTimeInterval(-1))

        XCTAssertTrue(expired.accountExpired)
        XCTAssertFalse(valid.accountExpired)
        XCTAssertEqual(expired.sourceKind, .xtream)
        XCTAssertEqual(expired.channels, 0)
        XCTAssertEqual(expired.duplicateChannels, 0)
    }

    func test_deletedSourceCannotProduceAReport() async throws {
        let database = try AppDatabase.makeInMemory()
        do {
            _ = try await GRDBSourceHealthReader(database: database).snapshot(playlistID: "missing", at: Date())
            XCTFail("Silinen kaynak rapor üretmemeli")
        } catch {
            XCTAssertEqual(error as? AppError, .notFound)
        }
    }
}
