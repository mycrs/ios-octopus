import XCTest
import OctopusDomain
@testable import OctopusData

final class SubscriptionSyncTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func fixture(
        provider: ContentProvider, status: SubscriptionStatus? = nil, expiresAt: Date? = nil,
        rejectsSubscriptionWrite: Bool = false
    ) async throws -> (ContentSyncService, GRDBPlaylistRepository, GRDBChannelRepository) {
        let database = try AppDatabase.makeInMemory()
        let playlists = GRDBPlaylistRepository(database: database, secrets: FakeSecretStore())
        try await playlists.add(Playlist(
            id: "p", name: "Personal source", kind: .sampleLibrary, createdAt: now,
            isActive: true, expiresAt: expiresAt, subscriptionStatus: status
        ), password: nil)
        try await CatalogWriter(database: database).replaceLiveCatalog(
            playlistID: "p", categories: [],
            channels: [Channel(id: "cached", playlistID: "p", name: "Cached", streamKey: "1")]
        )
        if rejectsSubscriptionWrite {
            try await database.write { db in
                try db.execute(sql: """
                    CREATE TRIGGER rejectSubscriptionWrite BEFORE UPDATE OF subscriptionStatus, expiresAt ON playlist
                    BEGIN SELECT RAISE(ABORT, 'subscription storage failure'); END
                    """)
            }
        }
        let date = now
        return (
            ContentSyncService(
                playlists: playlists, providerFactory: FakeProviderFactory(provider: provider),
                database: database, now: { date }
            ), playlists, GRDBChannelRepository(database: database)
        )
    }

    func test_expiredAuthenticationStopsAllCatalogRequestsAndPersistsBlock() async throws {
        let block = SubscriptionAccessBlock(status: .expired, expiresAt: now)
        let provider = FakeProvider(channels: [], authError: AppError.subscriptionUnavailable(block))
        let (service, playlists, _) = try await fixture(provider: provider)
        do {
            try await service.sync(playlistID: "p")
            XCTFail("Expired authentication must stop sync")
        } catch {
            XCTAssertEqual(error as? AppError, .subscriptionUnavailable(block))
        }
        let requests = await provider.catalogRequestCount
        let stored = try await playlists.playlist(id: "p")
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(stored?.subscriptionStatus, .expired)
        XCTAssertEqual(stored?.expiresAt, now)
    }

    func test_syncEnforcesDeadlineEvenWhenProviderReturnsAnAccount() async throws {
        let provider = FakeProvider(channels: [], accountExpiration: now, accountStatus: .active)
        let (service, playlists, _) = try await fixture(provider: provider)
        do {
            try await service.sync(playlistID: "p")
            XCTFail("All provider implementations must obey the same deadline")
        } catch {
            XCTAssertEqual(error as? AppError, .subscriptionUnavailable(
                SubscriptionAccessBlock(status: .expired, expiresAt: now)
            ))
        }
        let requests = await provider.catalogRequestCount
        let stored = try await playlists.playlist(id: "p")
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(stored?.subscriptionStatus, .expired)
    }

    func test_subscriptionWriteFailurePreservesDenialButDoesNotReportRenewalSuccess() async throws {
        let cachedDeadline = now.addingTimeInterval(60)
        for isDenied in [true, false] {
            let newDeadline = isDenied ? now : now.addingTimeInterval(7200)
            let provider = FakeProvider(channels: [], accountExpiration: newDeadline, accountStatus: .active)
            let (service, playlists, channels) = try await fixture(
                provider: provider, status: .active, expiresAt: cachedDeadline,
                rejectsSubscriptionWrite: true
            )
            do {
                try await service.sync(playlistID: "p")
                XCTFail("Neither a denied account nor a failed renewal write may continue sync")
            } catch {
                let expected: AppError = isDenied
                    ? .subscriptionUnavailable(SubscriptionAccessBlock(status: .expired, expiresAt: now))
                    : .storage(reason: "Veri kaydedilemedi")
                XCTAssertEqual(error as? AppError, expected)
            }
            let requests = await provider.catalogRequestCount
            let stored = try await playlists.playlist(id: "p")
            let cached = try await channels.channel(id: "cached")
            XCTAssertEqual(requests, 0)
            XCTAssertEqual(stored?.subscriptionStatus, .active)
            XCTAssertEqual(stored?.expiresAt, cachedDeadline)
            XCTAssertNotNil(cached)
        }
    }

    func test_bannedAccountDoesNotEraseCachedCatalogOrFetchNewContent() async throws {
        let block = SubscriptionAccessBlock(status: .banned, expiresAt: nil)
        let provider = FakeProvider(channels: [], authError: AppError.subscriptionUnavailable(block))
        let (service, playlists, channels) = try await fixture(provider: provider)
        do {
            try await service.sync(playlistID: "p")
            XCTFail("Banned account must stop sync")
        } catch {
            XCTAssertEqual(error as? AppError, .subscriptionUnavailable(block))
        }
        let stored = try await playlists.playlist(id: "p")
        let cached = try await channels.channel(id: "cached")
        let requests = await provider.catalogRequestCount
        XCTAssertEqual(stored?.subscriptionStatus, .banned)
        XCTAssertNotNil(cached)
        XCTAssertEqual(requests, 0)
    }

    func test_renewedAccountReplacesOldBlockBeforeNormalSync() async throws {
        let renewed = now.addingTimeInterval(60)
        let provider = FakeProvider(
            channels: [Channel(id: "new", playlistID: "p", name: "New", streamKey: "1")],
            accountExpiration: renewed, accountStatus: .active
        )
        let (service, playlists, channels) = try await fixture(
            provider: provider, status: .expired, expiresAt: now.addingTimeInterval(-60)
        )
        try await service.sync(playlistID: "p")
        let stored = try await playlists.playlist(id: "p")
        let requests = await provider.catalogRequestCount
        let channel = try await channels.channel(id: "new")
        XCTAssertNil(stored?.subscriptionBlock(at: now))
        XCTAssertEqual(stored?.subscriptionStatus, .active)
        XCTAssertEqual(stored?.expiresAt, renewed)
        XCTAssertEqual(stored?.name, "Personal source")
        XCTAssertEqual(stored?.isActive, true)
        XCTAssertGreaterThan(requests, 0)
        XCTAssertNotNil(channel)
    }

    func test_networkFailureDoesNotInventOrClearSubscriptionState() async throws {
        for status in [SubscriptionStatus.active, .expired] {
            let deadline = status == .active ? now.addingTimeInterval(60) : now.addingTimeInterval(-60)
            let provider = FakeProvider(channels: [], authError: AppError.network(reason: "offline"))
            let (service, playlists, _) = try await fixture(provider: provider, status: status, expiresAt: deadline)
            do {
                try await service.sync(playlistID: "p")
                XCTFail("Offline sync should fail without changing the account")
            } catch {
                XCTAssertEqual(error as? AppError, .network(reason: "offline"))
            }
            let stored = try await playlists.playlist(id: "p")
            let requests = await provider.catalogRequestCount
            XCTAssertEqual(stored?.subscriptionStatus, status)
            XCTAssertEqual(stored?.expiresAt, deadline)
            XCTAssertEqual(requests, 0)
        }
    }
}
