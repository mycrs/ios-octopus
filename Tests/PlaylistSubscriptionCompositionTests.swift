import XCTest
import OctopusCore
import OctopusData
import OctopusDomain
import OctopusNavigation
@testable import Octopus

@MainActor
final class PlaylistSubscriptionCompositionTests: XCTestCase {
    func test_expiredActiveSourceClearsOldRoutesAndPreservesItsSeparatePinLock() async throws {
        let database = try AppDatabase.makeInMemory()
        let repository = GRDBPlaylistRepository(database: database, secrets: SubscriptionCompositionSecrets())
        let playlist = Playlist(
            id: "protected-source", name: "Protected fixture", kind: .sampleLibrary,
            createdAt: Date(timeIntervalSince1970: 0), isActive: true,
            expiresAt: Date().addingTimeInterval(3600), subscriptionStatus: .active
        )
        try await repository.add(playlist, password: nil)
        let container = AppContainer(database: database, playlistAccessOverride: SubscriptionCompositionAccess())
        let settings = container.makeSettingsDependencies()
        await settings.notifyPlaylistChanged()
        XCTAssertTrue(container.isActivePlaylistLocked)
        XCTAssertNil(container.subscriptionState.block)
        container.router.selectedTab = .movies
        container.router.push(.movieDetail("old-movie"), in: .movies)
        container.router.presentPlayer(.movie("old-movie"))
        let expiredDeadline = Date(timeIntervalSince1970: 1_700_000_000)

        try await repository.updateSubscription(id: playlist.id, status: .expired, expiresAt: expiredDeadline)
        await settings.notifyPlaylistChanged()

        XCTAssertEqual(container.subscriptionState.playlistID, playlist.id)
        XCTAssertEqual(container.subscriptionState.block, SubscriptionAccessBlock(status: .expired, expiresAt: expiredDeadline))
        XCTAssertTrue(container.isActivePlaylistLocked, "Subscription blocking must not remove the independent PIN protection")
        XCTAssertFalse(container.isResolvingPlaylistAccess)
        XCTAssertEqual(container.activePlaylistName, playlist.name)
        XCTAssertEqual(container.router.selectedTab, .movies)
        XCTAssertNil(container.router.player)
        XCTAssertTrue(container.router.paths.values.allSatisfy { $0.isEmpty })
        XCTAssertFalse(container.router.needsOnboarding)
    }
}

private struct SubscriptionCompositionSecrets: SecretStore {
    func save(_ secret: String, for key: String) throws {}
    func read(for key: String) throws -> String? { nil }
    func delete(for key: String) throws {}
}

private struct SubscriptionCompositionAccess: PlaylistAccessControlling {
    func isProtected(_ id: Playlist.ID) async -> Bool { true }
    func isUnlocked(_ id: Playlist.ID) async -> Bool { false }
    func configure(_ id: Playlist.ID, pin: String) async throws {}
    func unlock(_ id: Playlist.ID, with pin: String) async -> Bool { false }
    func lockAll() async {}
    func remove(_ id: Playlist.ID) async {}
}
