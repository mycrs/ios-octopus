import XCTest
import GRDB
import OctopusDomain
@testable import OctopusData

final class SubscriptionPersistenceTests: XCTestCase {
    func test_additiveMigrationPreservesExistingSourceAndUserData() async throws {
        let queue = try DatabaseQueue(configuration: AppDatabase.makeConfiguration())
        try AppDatabase.migrator.migrate(queue, upTo: "v6_bolum_dogrudan_adres")
        try await queue.write { db in
            try db.execute(sql: "INSERT INTO playlist (id, name, kindType, createdAt, isActive, expiresAt) VALUES ('p', 'Personal', 'sampleLibrary', '2026-01-01', 1, '2030-01-01')")
            try db.execute(sql: "INSERT INTO channel (id, playlistId, name, streamKey, sortOrder, isAdult) VALUES ('c', 'p', 'Cached', '1', 0, 0)")
            try db.execute(sql: "INSERT INTO favorite (itemKey, addedAt) VALUES ('live:c', '2026-01-01')")
        }
        let database = try AppDatabase(queue)
        let repository = GRDBPlaylistRepository(database: database, secrets: FakeSecretStore())
        let stored = try await repository.playlist(id: "p")
        XCTAssertNil(stored?.subscriptionStatus)
        XCTAssertNotNil(stored?.expiresAt)
        XCTAssertEqual(stored?.name, "Personal")
        XCTAssertEqual(stored?.isActive, true)
        let counts = try await database.read { db in
            [try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM channel") ?? 0,
             try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM favorite") ?? 0]
        }
        XCTAssertEqual(counts, [1, 1])
    }

    func test_subscriptionUpdateCannotRevertSelectionOrPersonalSourceEdits() async throws {
        let database = try AppDatabase.makeInMemory()
        let repository = GRDBPlaylistRepository(database: database, secrets: FakeSecretStore())
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        try await repository.add(Playlist(
            id: "p", name: "Edited name", kind: .sampleLibrary, createdAt: date, isActive: true
        ), password: nil)
        try await repository.add(Playlist(id: "other", name: "Other", kind: .sampleLibrary, createdAt: date), password: nil)
        try await repository.setActive(id: "other")
        try await repository.updateSubscription(id: "p", status: .banned, expiresAt: date)
        let stored = try await repository.playlist(id: "p")
        let active = try await repository.activePlaylist()
        XCTAssertEqual(stored?.name, "Edited name")
        XCTAssertEqual(stored?.isActive, false)
        XCTAssertEqual(stored?.subscriptionStatus, .banned)
        XCTAssertEqual(stored?.expiresAt, date)
        XCTAssertEqual(active?.id, "other")
        try await repository.updateSubscription(id: "p", status: .active, expiresAt: nil)
        let renewed = try await repository.playlist(id: "p")
        XCTAssertEqual(renewed?.subscriptionStatus, .active)
        XCTAssertNil(renewed?.expiresAt)
        XCTAssertNil(renewed?.subscriptionBlock(at: date))
    }
}
