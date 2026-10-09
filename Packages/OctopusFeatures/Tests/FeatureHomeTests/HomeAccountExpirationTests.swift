import XCTest
import OctopusDomain
@testable import FeatureHome

final class HomeAccountExpirationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func account(secondsRemaining: TimeInterval?) -> HomeAccount {
        HomeAccount(playlist: Playlist(
            id: "test", name: "Test", kind: .sampleLibrary, createdAt: now,
            expiresAt: secondsRemaining.map { now.addingTimeInterval($0) }
        ), now: now)
    }

    func test_lessThanOneDayIsSoonUntilTheActualDeadline() {
        for seconds: TimeInterval in [1, 3_600, 86_399] {
            let value = account(secondsRemaining: seconds)
            XCTAssertEqual(value.remainingDays, 0)
            XCTAssertEqual(value.urgency, .soon)
            XCTAssertEqual(value.expiryText, "1 günden az kaldı")
        }
    }

    func test_exactDeadlineAndPastAreExpired() {
        for seconds: TimeInterval in [0, -1, -86_400] {
            let value = account(secondsRemaining: seconds)
            XCTAssertEqual(value.urgency, .expired)
            XCTAssertEqual(value.expiryText, "Aboneliğin süresi doldu")
        }
    }

    func test_sourceWithoutDeadlineDoesNotAcquireExpiration() {
        let value = account(secondsRemaining: nil)
        XCTAssertNil(value.remainingDays)
        XCTAssertNil(value.expiryText)
        XCTAssertEqual(value.urgency, .normal)
    }
}
