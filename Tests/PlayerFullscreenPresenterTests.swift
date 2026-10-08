import XCTest
@testable import Octopus

final class PlayerFullscreenPresenterTests: XCTestCase {
    func test_samePlayerRefresh_updatesContentWithoutAnotherPresentation() {
        var state = PlayerFullscreenPresentationState()
        state.request("a")
        XCTAssertEqual(state.nextAction(), .present("a"))
        state.didPresent("a")
        state.request("a")

        XCTAssertEqual(state.nextAction(), .update("a"))
        XCTAssertEqual(state.displayedID, "a")
        XCTAssertNil(state.transitioningID)
    }

    func test_closeWhilePresenting_waitsForPresentationThenDismisses() {
        var state = PlayerFullscreenPresentationState()
        state.request("a")
        XCTAssertEqual(state.nextAction(), .present("a"))
        state.request(nil)
        XCTAssertNil(state.nextAction())
        state.didPresent("a")

        XCTAssertEqual(state.nextAction(), .dismiss("a"))
        state.didDismiss("a")
        XCTAssertNil(state.nextAction())
    }

    func test_replacementWaitsForOwnedDismissalAndUsesLatestSelection() {
        var state = PlayerFullscreenPresentationState()
        state.request("a")
        _ = state.nextAction()
        state.didPresent("a")
        state.request("b")
        XCTAssertEqual(state.nextAction(), .dismiss("a"))
        state.request("c")
        XCTAssertNil(state.nextAction())
        state.didDismiss("a")

        XCTAssertEqual(state.nextAction(), .present("c"))
        XCTAssertEqual(state.displayedID, "c")
    }

    func test_oldCompletionCannotDismissNewPresentation() {
        var state = PlayerFullscreenPresentationState()
        state.request("a")
        _ = state.nextAction()
        state.didPresent("a")
        state.request("b")
        _ = state.nextAction()
        state.didDismiss("a")
        _ = state.nextAction()
        state.didDismiss("a")
        state.didPresent("a")

        XCTAssertEqual(state.displayedID, "b")
        XCTAssertEqual(state.transitioningID, "b")
        XCTAssertNil(state.nextAction())
        state.didPresent("b")
        XCTAssertEqual(state.nextAction(), .update("b"))
    }

    func test_latePresentationCompletionCannotReleaseDismissalBarrier() {
        var state = PlayerFullscreenPresentationState()
        state.request("a")
        _ = state.nextAction()
        state.didPresent("a")
        state.request("b")
        XCTAssertEqual(state.nextAction(), .dismiss("a"))
        state.didPresent("a")

        XCTAssertEqual(state.displayedID, "a")
        XCTAssertNil(state.nextAction())
        state.didDismiss("a")
        XCTAssertEqual(state.nextAction(), .present("b"))
    }
}
