import XCTest
import UIKit
@testable import Octopus

@MainActor
final class PlayerOrientationPolicyTests: XCTestCase {
    func test_orientationDenialKeepsOnlyKnownSupportedMask() {
        let prefix = "None of the requested orientations are supported by the view controller. Requested: landscapeLeft, landscapeRight; Supported: "
        XCTAssertEqual(PlayerOrientationRequestDiagnostics.deniedMask(in: prefix + "portrait"), .portrait)
        XCTAssertEqual(PlayerOrientationRequestDiagnostics.deniedMask(in: prefix + "landscapeLeft, landscapeRight."), .landscape)
    }

    func test_orientationDenialRejectsArbitrarySuffixAndUnknownDescriptions() {
        let prefix = "None of the requested orientations are supported by the view controller. Requested: landscapeLeft; Supported: "
        for suffix in ["", "portrait portrait", "portrait, portrait", "portrait https://example.invalid/channel",
                       "portrait; title=Private", "portrait, unknown"] {
            XCTAssertNil(PlayerOrientationRequestDiagnostics.deniedMask(in: prefix + suffix))
        }
        XCTAssertNil(PlayerOrientationRequestDiagnostics.deniedMask(in: "Private controller failed: portrait"))
    }

    func test_initialLayoutCannotLockBeforeLandscapeRequestIsIssued() {
        var state = PlayerFullscreenOrientationLockState()
        let landscape = CGSize(width: 1376, height: 1032)
        XCTAssertFalse(state.observe(orientation: .landscapeRight, viewSize: landscape, windowSize: landscape))
        XCTAssertFalse(state.prefersLocked)
        state.didRequestLandscape()
        XCTAssertTrue(state.observe(orientation: .landscapeRight, viewSize: landscape, windowSize: landscape))
        XCTAssertTrue(state.prefersLocked)
    }

    func test_portraitSceneCannotBeLockedBeforeLandscapeTransition() {
        var state = PlayerFullscreenOrientationLockState()
        state.didRequestLandscape()
        XCTAssertFalse(state.prefersLocked)
        XCTAssertFalse(state.observe(orientation: .portrait,
                                     viewSize: CGSize(width: 1376, height: 1032),
                                     windowSize: CGSize(width: 1376, height: 1032)))
        XCTAssertFalse(state.prefersLocked)
    }

    func test_landscapeSceneWaitsForBothViewAndWindowGeometry() {
        var state = PlayerFullscreenOrientationLockState()
        state.didRequestLandscape()
        let portrait = CGSize(width: 1032, height: 1376)
        let landscape = CGSize(width: 1376, height: 1032)
        XCTAssertFalse(state.observe(orientation: .landscapeRight, viewSize: portrait, windowSize: landscape))
        XCTAssertFalse(state.observe(orientation: .landscapeRight, viewSize: landscape, windowSize: portrait))
        XCTAssertFalse(state.observe(orientation: .landscapeRight, viewSize: .zero, windowSize: .zero))
        XCTAssertTrue(state.observe(orientation: .landscapeRight, viewSize: landscape, windowSize: landscape))
        XCTAssertTrue(state.prefersLocked)
        XCTAssertFalse(state.observe(orientation: .landscapeRight, viewSize: landscape, windowSize: landscape))
    }

    func test_landscapeLockSurvivesPortraitDevicePostureUntilDismissal() {
        var state = PlayerFullscreenOrientationLockState()
        state.didRequestLandscape()
        let landscape = CGSize(width: 874, height: 402)
        XCTAssertTrue(state.observe(orientation: .landscapeLeft, viewSize: landscape, windowSize: landscape))
        XCTAssertFalse(state.observe(orientation: .portrait, viewSize: landscape, windowSize: landscape))
        XCTAssertTrue(state.prefersLocked)
        XCTAssertTrue(state.beginDismissal())
        XCTAssertFalse(state.prefersLocked)
        XCTAssertTrue(state.isClosing)
        XCTAssertFalse(state.beginDismissal())
        XCTAssertFalse(state.observe(orientation: .landscapeRight, viewSize: landscape, windowSize: landscape))
    }

    func test_dismissalBeforeRotationCompletionCannotRelockPlayer() {
        var state = PlayerFullscreenOrientationLockState()
        XCTAssertTrue(state.beginDismissal())
        let landscape = CGSize(width: 1376, height: 1032)
        state.didRequestLandscape()
        XCTAssertFalse(state.observe(orientation: .landscapeRight, viewSize: landscape, windowSize: landscape))
        XCTAssertFalse(state.prefersLocked)
        XCTAssertTrue(state.isClosing)
    }

    func test_fullscreenRestrictsItsSceneAndRestoresPreviousOrientation() {
        let policy = PlayerOrientationPolicy()
        let scene = NSObject()
        let id = ObjectIdentifier(scene)
        let lease = policy.acquire(sceneID: id, orientation: .portrait)

        XCTAssertEqual(policy.supportedOrientations(sceneID: id, isPad: false), .landscape)
        XCTAssertEqual(policy.release(sceneID: id, lease: lease), .portrait)
        XCTAssertEqual(policy.supportedOrientations(sceneID: id, isPad: false), .allButUpsideDown)
    }

    func test_otherIPadWindowKeepsItsSupportedOrientations() {
        let policy = PlayerOrientationPolicy()
        let playerScene = NSObject()
        let otherScene = NSObject()
        _ = policy.acquire(sceneID: ObjectIdentifier(playerScene), orientation: .portrait)

        XCTAssertEqual(policy.supportedOrientations(sceneID: ObjectIdentifier(otherScene), isPad: true), .all)
        XCTAssertEqual(policy.supportedOrientations(sceneID: nil, isPad: true), .all)
    }

    func test_nestedLeaseAndStaleReleaseCannotUnlockCurrentPlayer() {
        let policy = PlayerOrientationPolicy()
        let scene = NSObject()
        let id = ObjectIdentifier(scene)
        let first = policy.acquire(sceneID: id, orientation: .landscapeRight)
        let second = policy.acquire(sceneID: id, orientation: .portrait)

        XCTAssertNil(policy.release(sceneID: id, lease: first))
        XCTAssertNil(policy.release(sceneID: id, lease: first))
        XCTAssertNil(policy.release(sceneID: id, lease: UUID()))
        XCTAssertTrue(policy.supportsLandscapeOnly(sceneID: id))
        XCTAssertEqual(policy.release(sceneID: id, lease: second), .landscapeRight)
        XCTAssertFalse(policy.supportsLandscapeOnly(sceneID: id))
    }

    func test_destroyedSceneCanStillReleaseItsRestrictionByCapturedIdentity() throws {
        let policy = PlayerOrientationPolicy()
        var scene: NSObject? = NSObject()
        let id = ObjectIdentifier(try XCTUnwrap(scene))
        let lease = policy.acquire(sceneID: id, orientation: .portrait)
        scene = nil

        XCTAssertEqual(policy.release(sceneID: id, lease: lease), .portrait)
        XCTAssertFalse(policy.supportsLandscapeOnly(sceneID: id))
    }
}
