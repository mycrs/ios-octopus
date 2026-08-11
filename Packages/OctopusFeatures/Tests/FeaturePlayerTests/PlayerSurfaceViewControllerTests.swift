import SwiftUI
import UIKit
import XCTest
@testable import FeaturePlayer

@MainActor
final class PlayerSurfaceViewControllerTests: XCTestCase {

    func test_hostedOverlayKeepsRootStoreWhenContentChanges() {
        let store = PlayerHostedOverlayStore(
            content: Text("Bir"),
            brandColor: .blue
        )
        let controller = PlayerSurfaceViewController(
            surface: UIView(),
            surfaceGeneration: 1,
            overlay: PlayerHostedOverlay(store: store)
        )
        controller.loadViewIfNeeded()

        store.update(content: Text("İki"), brandColor: .red)
        controller.update(surfaceGeneration: 1, makeSurface: { nil })

        XCTAssertTrue(controller.overlayHost.rootView.store === store)
    }

    func test_replacesOnlyVideoSurfaceWhenEngineChanges() {
        let firstSurface = UIView()
        let controller = PlayerSurfaceViewController(
            surface: firstSurface,
            surfaceGeneration: 1,
            overlay: EmptyView()
        )
        controller.loadViewIfNeeded()
        let originalHost = controller.overlayHost
        let replacementSurface = UIView()

        controller.update(
            surfaceGeneration: 2,
            makeSurface: { replacementSurface }
        )
        let lateRenderer = UIView()
        replacementSurface.addSubview(lateRenderer)

        controller.update(
            surfaceGeneration: 2,
            makeSurface: {
                XCTFail("Aynı nesilde video yüzeyi yeniden oluşturulmamalı")
                return nil
            }
        )

        XCTAssertNil(firstSurface.superview)
        XCTAssertTrue(replacementSurface.superview === controller.view)
        XCTAssertTrue(controller.overlayHost === originalHost)
        XCTAssertTrue(originalHost.view.superview === replacementSurface)
        XCTAssertTrue(replacementSurface.subviews.last === originalHost.view)
        XCTAssertTrue(replacementSurface.clipsToBounds)
        XCTAssertGreaterThan(
            originalHost.view.layer.zPosition,
            lateRenderer.layer.zPosition
        )
    }
}
