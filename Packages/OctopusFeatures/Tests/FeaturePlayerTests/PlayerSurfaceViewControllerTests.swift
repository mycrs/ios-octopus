import SwiftUI
import UIKit
import XCTest
@testable import FeaturePlayer

@MainActor
final class PlayerSurfaceViewControllerTests: XCTestCase {

    func test_edgeGlyphPathsStayInsideControlBounds() {
        let controlBounds = CGRect(x: 0, y: 0, width: 44, height: 44)
        let glyphBounds = [
            PlayerCloseGlyph().path(in: controlBounds).boundingRect,
            PlayerOptionsGlyph().path(in: controlBounds).boundingRect
        ]

        for bounds in glyphBounds {
            XCTAssertFalse(bounds.isEmpty)
            XCTAssertTrue(controlBounds.contains(bounds))
        }
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
            makeSurface: { replacementSurface },
            overlay: EmptyView()
        )
        let lateRenderer = UIView()
        replacementSurface.addSubview(lateRenderer)

        controller.update(
            surfaceGeneration: 2,
            makeSurface: {
                XCTFail("Aynı nesilde video yüzeyi yeniden oluşturulmamalı")
                return nil
            },
            overlay: EmptyView()
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
