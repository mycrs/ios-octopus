import SwiftUI
import UIKit
import XCTest
@testable import FeaturePlayer

@MainActor
final class PlayerSurfaceViewControllerTests: XCTestCase {

    func test_edgeControlImagesKeepOriginalRendering() {
        for glyph in [PlayerEdgeGlyph.close, .options] {
            let image = PlayerEdgeControlImage.image(for: glyph)
            XCTAssertEqual(image.size, PlayerEdgeControlImage.size)
            XCTAssertEqual(image.renderingMode, .alwaysOriginal)
            XCTAssertNotNil(image.cgImage)
        }
    }

    func test_edgeControlUsesOneAccessibleBitmapLayer() {
        let control = PlayerEdgeControlView()
        control.glyph = .options
        control.isAccessibilityElement = true
        control.accessibilityTraits = .button
        control.accessibilityLabel = "Seçenekler"

        XCTAssertNotNil(control.imageView.image?.cgImage)
        XCTAssertTrue(control.isAccessibilityElement)
        XCTAssertTrue(control.accessibilityTraits.contains(.button))
        XCTAssertEqual(control.accessibilityLabel, "Seçenekler")
    }

    func test_overlayWindowPassesEmptySpaceThrough() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let window = PlayerPassThroughWindow(frame: frame)
        let root = UIViewController()
        root.view.frame = frame
        let control = UIControl(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        root.view.addSubview(control)
        window.rootViewController = root
        window.isHidden = false
        window.layoutIfNeeded()

        XCTAssertTrue(window.hitTest(CGPoint(x: 22, y: 22), with: nil) === control)
        XCTAssertNil(window.hitTest(CGPoint(x: 80, y: 80), with: nil))
    }

    func test_overlayHostAlwaysHidesStatusBar() {
        let host = PlayerOverlayHostingController(rootView: EmptyView())
        XCTAssertTrue(host.prefersStatusBarHidden)
    }

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
