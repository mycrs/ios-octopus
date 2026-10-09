import Foundation
import XCTest
@testable import FeaturePlayer

final class PlayerControlsPressStateTests: XCTestCase {
    func test_buttonReleaseRestartsTimerOnlyAfterAnActualPress() {
        let state = PlayerControlsPressState()
        let id = UUID()
        XCTAssertFalse(state.isPressed)
        XCTAssertFalse(state.end(id))
        state.begin(id)
        XCTAssertTrue(state.isPressed)
        XCTAssertTrue(state.end(id))
        XCTAssertFalse(state.isPressed)
    }

    func test_overlappingControlsRemainProtectedUntilBothRelease() {
        let state = PlayerControlsPressState()
        let close = UUID(), playback = UUID()
        state.begin(close)
        state.begin(playback)
        XCTAssertFalse(state.end(close))
        XCTAssertTrue(state.isPressed)
        XCTAssertTrue(state.end(playback))
        XCTAssertFalse(state.isPressed)
    }

    func test_repeatedPressNotificationsDoNotRequireMultipleReleases() {
        let state = PlayerControlsPressState()
        let id = UUID()
        state.begin(id)
        state.begin(id)
        XCTAssertTrue(state.end(id))
        XCTAssertFalse(state.end(id))
        XCTAssertFalse(state.isPressed)
    }

    func test_disappearanceOfAnUnpressedControlCannotReleaseAnotherPress() {
        let state = PlayerControlsPressState()
        let held = UUID()
        state.begin(held)
        XCTAssertFalse(state.end(UUID()))
        XCTAssertTrue(state.isPressed)
        XCTAssertTrue(state.end(held))
    }

    func test_lateReleaseFromOldControlCannotEndItsReplacement() {
        let state = PlayerControlsPressState()
        let old = UUID(), replacement = UUID()
        state.begin(old)
        XCTAssertTrue(state.end(old))
        state.begin(replacement)
        XCTAssertFalse(state.end(old))
        XCTAssertTrue(state.isPressed)
        XCTAssertTrue(state.end(replacement))
    }
}
