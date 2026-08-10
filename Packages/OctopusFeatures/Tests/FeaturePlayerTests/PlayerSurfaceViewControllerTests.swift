import SwiftUI
import UIKit
import XCTest
@testable import FeaturePlayer

@MainActor
final class PlayerSurfaceViewControllerTests: XCTestCase {

    func test_replacesOnlyVideoSurfaceWhenEngineChanges() {
        let firstSurface = UIView()
        let controller = PlayerSurfaceViewController(
            surface: firstSurface,
            surfaceGeneration: 1,
            overlay: AnyView(EmptyView())
        )
        controller.loadViewIfNeeded()
        let originalHost = controller.overlayHost
        let replacementSurface = UIView()

        controller.update(
            surfaceGeneration: 2,
            makeSurface: { replacementSurface },
            overlay: AnyView(EmptyView())
        )

        XCTAssertNil(firstSurface.superview)
        XCTAssertTrue(replacementSurface.superview === controller.view)
        XCTAssertTrue(controller.overlayHost === originalHost)
        XCTAssertTrue(controller.view.subviews.last === originalHost.view)
    }
}
