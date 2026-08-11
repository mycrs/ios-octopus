import XCTest
import OctopusDesignSystem

@MainActor
final class LanguageControllerTests: XCTestCase {
    private var store: UserDefaults!
    private let suiteName = "language.tests"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suiteName)
        store = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func test_systemUsesTurkishForTurkishDevice() {
        let controller = LanguageController(
            store: store,
            preferredLanguages: { ["tr-TR"] }
        )

        XCTAssertEqual(controller.selection, .system)
        XCTAssertEqual(controller.resolvedLanguageCode, "tr")
    }

    func test_systemFallsBackToEnglishForOtherDeviceLanguages() {
        let controller = LanguageController(
            store: store,
            preferredLanguages: { ["de-DE"] }
        )

        XCTAssertEqual(controller.resolvedLanguageCode, "en")
    }

    func test_explicitSelectionOverridesDeviceLanguage() {
        let controller = LanguageController(
            store: store,
            preferredLanguages: { ["tr-TR"] }
        )

        controller.select(.english)

        XCTAssertEqual(controller.resolvedLanguageCode, "en")
    }

    func test_selectionSurvivesRelaunch() {
        let first = LanguageController(store: store)
        first.select(.turkish)

        let second = LanguageController(
            store: store,
            preferredLanguages: { ["en-US"] }
        )

        XCTAssertEqual(second.selection, .turkish)
        XCTAssertEqual(second.resolvedLanguageCode, "tr")
    }
}
