import XCTest
import OctopusDomain
@testable import FeatureSettings

@MainActor
final class SampleLibrarySettingsModelTests: XCTestCase {
    func test_settingsEntryDoesNotInstallUntilUserChoosesAndDoesNotRepeatAfterSuccess() async {
        var installs = 0
        let model = SampleLibrarySettingsModel { installs += 1 }
        XCTAssertEqual(installs, 0)

        await model.install()
        await model.install()

        XCTAssertEqual(installs, 1)
        XCTAssertEqual(model.state, .installed)
        XCTAssertNil(model.errorMessage)
    }

    func test_failureAllowsRetryWithoutReportingReady() async {
        var installs = 0
        let model = SampleLibrarySettingsModel {
            installs += 1
            if installs == 1 { throw AppError.storage(reason: "Örnek hata") }
        }

        await model.install()
        XCTAssertEqual(model.state, .idle)
        XCTAssertNotNil(model.errorMessage)

        await model.install()
        XCTAssertEqual(model.state, .installed)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(installs, 2)
    }

    func test_cancellationDoesNotReportReady() async {
        let model = SampleLibrarySettingsModel { throw CancellationError() }

        await model.install()

        XCTAssertEqual(model.state, .idle)
        XCTAssertNil(model.errorMessage)
    }
}
