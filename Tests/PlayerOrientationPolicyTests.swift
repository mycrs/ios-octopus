import XCTest
import UIKit
@testable import Octopus

@MainActor
final class PlayerOrientationPolicyTests: XCTestCase {
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
