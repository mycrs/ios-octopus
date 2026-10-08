import XCTest
import SwiftUI
import OctopusDomain
// `@testable` değil: ThemeController'ın tamamı public API ve farklı bir
// paketten geliyor. Testler onu uygulamanın gördüğü yüzeyden kullanmalı.
import OctopusDesignSystem

/// Marka rengi öncelik sırası: mavi ürün kimliği ve kalıcı kullanıcı tonu.
@MainActor
final class ThemeControllerTests: XCTestCase {

    private var store: UserDefaults!
    private let suiteName = "theme.tests"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suiteName)
        store = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func brand(
        _ hex: String?,
        name: String? = nil,
        logoURL: URL? = nil
    ) -> BrandConfiguration {
        BrandConfiguration(primaryColorHex: hex, resellerName: name, logoURL: logoURL)
    }

    // MARK: - Öncelik sırası

    func test_brightAccentsUseDarkButtonText() {
        for selection in Theme.BrandColor.allCases {
            XCTAssertEqual(Theme.contentColor(on: selection.color), Color.black)
        }
    }

    func test_darkResellerAccentUsesLightButtonText() {
        XCTAssertEqual(Theme.contentColor(on: Theme.Palette.surface), Color.white)
    }

    func test_defaultsToAppColorWhenNothingConfigured() {
        let controller = ThemeController(store: store)
        XCTAssertEqual(controller.selection, .default)
        XCTAssertNil(controller.remoteColor)
        XCTAssertEqual(controller.accent, Theme.Palette.accent)
    }

    func test_panelColorCannotReplaceProductBlue() {
        let controller = ThemeController(store: store)
        controller.apply(branding: brand("#00E676"))

        XCTAssertNotNil(controller.remoteColor)
        XCTAssertEqual(controller.accent, Theme.Palette.accent)
    }

    func test_userSelectionOverridesPanel() {
        // Bayi markasını uygulamak istiyoruz ama kullanıcının bilinçli
        // tercihini ezmemeliyiz.
        let controller = ThemeController(store: store)
        controller.apply(branding: brand("#00E676"))
        controller.select(.purple)

        XCTAssertEqual(controller.accent, Theme.BrandColor.purple.color)
        XCTAssertNotNil(controller.remoteColor, "Panel rengi unutulmamalı")
    }

    func test_returningToDefaultRestoresProductBlue() {
        let controller = ThemeController(store: store)
        controller.apply(branding: brand("#00E676"))
        controller.select(.orange)
        controller.select(.default)

        XCTAssertEqual(controller.accent, Theme.Palette.accent)
    }

    // MARK: - Kalıcılık

    func test_userSelectionSurvivesRelaunch() {
        let first = ThemeController(store: store)
        first.select(.green)

        let second = ThemeController(store: store)
        XCTAssertEqual(second.selection, .green)
        XCTAssertEqual(second.accent, Theme.BrandColor.green.color)
    }

    // MARK: - Geçersiz panel verisi

    func test_panelDefaultRedIsNotApplied() {
        // Panel renk seçilmediğinde eski kırmızı varsayılanı gönderiyor.
        let controller = ThemeController(store: store)
        controller.apply(branding: brand("#E50914"))

        XCTAssertNil(controller.remoteColor)
        XCTAssertEqual(controller.accent, Theme.Palette.accent)
    }

    func test_adminSelectedRedCannotReplaceProductBlue() {
        let controller = ThemeController(store: store)
        controller.apply(branding: brand("#FF3B30"))

        XCTAssertNotNil(controller.remoteColor)
        XCTAssertEqual(controller.accent, Theme.Palette.accent)
    }

    func test_invalidHexIsIgnored() {
        let controller = ThemeController(store: store)
        controller.apply(branding: brand("mavi"))
        XCTAssertNil(controller.remoteColor)
    }

    func test_nilBrandingClearsRemoteColor() {
        let controller = ThemeController(store: store)
        controller.apply(branding: brand("#00E676"))
        XCTAssertNotNil(controller.remoteColor)

        controller.apply(branding: nil)
        XCTAssertNil(controller.remoteColor, "Panel markayı kaldırınca renk de gitmeli")
    }

    // MARK: - Bayi adı

    func test_resellerNameIsExposed() {
        let controller = ThemeController(store: store)
        controller.apply(branding: brand("#00E676", name: "Bayi A"))
        XCTAssertEqual(controller.resellerName, "Bayi A")

        controller.apply(branding: nil)
        XCTAssertNil(controller.resellerName)
    }

    func test_remoteLogoCannotReplaceProductEmblem() {
        let controller = ThemeController(store: store)
        let logo = URL(string: "https://example.com/logo.png")

        controller.apply(branding: brand(nil, logoURL: logo))
        XCTAssertNil(controller.logoURL)

        controller.apply(branding: nil)
        XCTAssertNil(controller.logoURL)
    }
}
