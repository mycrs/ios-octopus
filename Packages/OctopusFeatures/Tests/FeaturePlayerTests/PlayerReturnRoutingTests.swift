import XCTest
import OctopusDomain
import OctopusNavigation

@MainActor
final class PlayerReturnRoutingTests: XCTestCase {
    private func makeRouter() -> AppRouter {
        let suite = "PlayerReturnRoutingTests.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite) ?? .standard
        store.removePersistentDomain(forName: suite)
        return AppRouter(store: store)
    }

    func test_fullscreenDismiss_returnsToOriginWithoutPoppingItsPath() throws {
        let router = makeRouter()
        router.selectedTab = .series
        router.push(.seriesDetail("s"))
        router.presentPlayer(.episode("e"))
        let presentation = try XCTUnwrap(router.player)

        router.dismissPlayer(ifPresented: presentation.id)

        XCTAssertEqual(router.selectedTab, .series)
        XCTAssertEqual(router.paths[.series]?.count, 1)
        XCTAssertNil(router.player)
    }

    func test_pushedLiveScreen_receivesFullscreenWithoutReturningToHomeRoot() throws {
        let router = makeRouter()
        router.push(.channels(categoryID: nil))
        router.registerLivePreview(ownerID: UUID())
        router.presentPlayer(.liveChannel("a"))
        let presentation = try XCTUnwrap(router.player)

        XCTAssertTrue(router.canReturnToLivePreview(from: presentation))
        router.dismissPlayer(ifPresented: presentation.id)
        XCTAssertEqual(router.selectedTab, .home)
        XCTAssertEqual(router.paths[.home]?.count, 1)
        XCTAssertTrue(router.canReturnToLivePreview(from: presentation))
    }

    func test_hiddenLiveReceiver_doesNotPreserveInvisibleAudio() throws {
        let router = makeRouter()
        router.selectedTab = .live
        router.registerLivePreview(ownerID: UUID())
        router.push(.channelGuide("a"))
        router.presentPlayer(.liveChannel("a"))
        let presentation = try XCTUnwrap(router.player)

        XCTAssertFalse(presentation.returnsToLivePreview)
        XCTAssertFalse(router.canReturnToLivePreview(from: presentation))
    }

    func test_homeAndSearchPlayer_withoutLiveReceiver_cannotHandOff() throws {
        let router = makeRouter()
        router.push(.search)
        router.presentPlayer(.liveChannel("a"))

        XCTAssertFalse(router.canReturnToLivePreview(from: try XCTUnwrap(router.player)))
    }

    func test_stalePresentationAndReceiverCleanup_cannotDismissTheirReplacements() throws {
        let router = makeRouter()
        router.selectedTab = .live
        let oldOwner = UUID()
        router.registerLivePreview(ownerID: oldOwner)
        router.presentPlayer(.liveChannel("a"))
        let old = try XCTUnwrap(router.player)
        router.registerLivePreview(ownerID: UUID())
        router.presentPlayer(.liveChannel("a"))
        let replacement = try XCTUnwrap(router.player)

        router.unregisterLivePreview(ownerID: oldOwner)
        router.dismissPlayer(ifPresented: old.id)

        XCTAssertNotEqual(old.id, replacement.id)
        XCTAssertEqual(router.player, replacement)
        XCTAssertTrue(router.canReturnToLivePreview(from: replacement))
        XCTAssertFalse(router.canReturnToLivePreview(from: old))
    }

    func test_sourceReset_invalidatesPreviouslyVisibleReceiver() throws {
        let router = makeRouter()
        router.selectedTab = .live
        router.registerLivePreview(ownerID: UUID())
        router.presentPlayer(.liveChannel("a"))
        let presentation = try XCTUnwrap(router.player)

        router.resetAfterPlaylistChange()

        XCTAssertFalse(router.canReturnToLivePreview(from: presentation))
        XCTAssertNil(router.player)
    }
}
