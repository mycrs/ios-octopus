import XCTest
import OctopusDomain
@testable import FeatureOnboarding

@MainActor
final class SampleLibraryOnboardingModelTests: XCTestCase {
    func test_installationRequiresExplicitCallAndCompletesOnlyOnce() async {
        var installs = 0
        let model = SampleLibraryOnboardingModel { installs += 1 }
        XCTAssertEqual(installs, 0)
        XCTAssertEqual(model.state, .idle)

        let completed = await model.install()
        let repeated = await model.install()

        XCTAssertTrue(completed)
        XCTAssertFalse(repeated)
        XCTAssertEqual(model.state, .installed)
        XCTAssertEqual(installs, 1)
    }

    func test_secondTapWhileInstallerRunsDoesNotStartAnotherInstallation() async {
        var installs = 0
        var model: SampleLibraryOnboardingModel?
        model = SampleLibraryOnboardingModel {
            installs += 1
            guard let current = model else {
                XCTFail("Kurulum modeli eksik")
                return
            }
            XCTAssertEqual(current.state, .installing)
            let duplicate = await current.install()
            XCTAssertFalse(duplicate)
            XCTAssertEqual(current.state, .installing)
        }

        let completed = await model?.install()

        XCTAssertEqual(completed, true)
        XCTAssertEqual(installs, 1)
        XCTAssertEqual(model?.state, .installed)
    }

    func test_failureStaysOnEntryAndAllowsAnExplicitRetry() async {
        var installs = 0
        let model = SampleLibraryOnboardingModel {
            installs += 1
            if installs == 1 { throw AppError.storage(reason: "Örnek hata") }
        }

        let first = await model.install()
        XCTAssertFalse(first)
        XCTAssertEqual(model.state, .idle)
        XCTAssertNotNil(model.errorMessage)

        let retry = await model.install()
        XCTAssertTrue(retry)
        XCTAssertEqual(model.state, .installed)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(installs, 2)
    }

    func test_cancellationDoesNotCompleteOnboarding() async {
        let model = SampleLibraryOnboardingModel { throw CancellationError() }

        let completed = await model.install()

        XCTAssertFalse(completed)
        XCTAssertEqual(model.state, .idle)
        XCTAssertNil(model.errorMessage)
    }

    func test_unexpectedErrorDoesNotExposeRawErrorDetails() async {
        let model = SampleLibraryOnboardingModel {
            throw NSError(domain: "private-installation-detail", code: 1)
        }

        let completed = await model.install()

        XCTAssertFalse(completed)
        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(model.errorMessage, "Örnek kütüphane hazırlanamadı. Tekrar dene.")
    }
}
