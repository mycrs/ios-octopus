import XCTest
import SwiftUI
import Combine
@testable import FeaturePlayer

@MainActor
final class PlayerHostedOverlayTests: XCTestCase {
    func test_updateDoesNotPublishDuringRenderAndCoalescesLatestContent() async {
        let store = PlayerHostedOverlayStore(content: Text("initial"), brandColor: .red)
        let published = expectation(description: "Latest overlay published")
        var publications = 0
        let subscription = store.$snapshot.sink { snapshot in
            publications += 1
            if snapshot.brandColor == .green { published.fulfill() }
        }

        store.update(content: Text("intermediate"), brandColor: .blue)
        store.update(content: Text("latest"), brandColor: .green)
        XCTAssertEqual(publications, 1, "UIViewController update must not synchronously publish")
        XCTAssertEqual(store.snapshot.brandColor, .red)
        await fulfillment(of: [published], timeout: 1)
        XCTAssertEqual(store.snapshot.brandColor, .green)
        XCTAssertEqual(publications, 2, "A render pass should publish only its latest overlay")
        subscription.cancel()
    }

    func test_dismantledOverlayCannotPublishQueuedUpdate() async {
        let store = PlayerHostedOverlayStore(content: Text("initial"), brandColor: .red)
        let unexpected = expectation(description: "Detached overlay update")
        unexpected.isInverted = true
        let subscription = store.$snapshot.dropFirst().sink { _ in unexpected.fulfill() }

        store.update(content: Text("detached"), brandColor: .blue)
        store.cancelPendingUpdate()
        await fulfillment(of: [unexpected], timeout: 0.1)
        XCTAssertEqual(store.snapshot.brandColor, .red)
        subscription.cancel()
    }
}
