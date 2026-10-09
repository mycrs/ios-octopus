import XCTest
@testable import OctopusDomain

final class SubscriptionAccessTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func test_expirationUsesExactInstantInsteadOfRemainingWholeDays() {
        let upcoming = now.addingTimeInterval(1)
        let playlist = Playlist(
            id: "p", name: "Source", kind: .sampleLibrary, createdAt: now,
            expiresAt: upcoming, subscriptionStatus: .active
        )
        XCTAssertEqual(playlist.remainingDays(from: now), 0)
        XCTAssertNil(playlist.subscriptionBlock(at: now))
        XCTAssertEqual(playlist.subscriptionBlock(at: upcoming)?.status, .expired)
        XCTAssertEqual(playlist.subscriptionBlock(at: upcoming.addingTimeInterval(1))?.status, .expired)
    }

    func test_blockedStatusesDoNotDependOnHavingAnExpirationDate() {
        for status in [SubscriptionStatus.expired, .inactive, .disabled, .banned] {
            let block = SubscriptionAccessBlock.evaluate(status: status, expiresAt: nil, at: now)
            XCTAssertEqual(block?.status, status)
            XCTAssertFalse(AppError.subscriptionUnavailable(SubscriptionAccessBlock(
                status: status, expiresAt: nil
            )).isRetryable)
        }
        XCTAssertNil(SubscriptionAccessBlock.evaluate(status: .active, expiresAt: nil, at: now))
        XCTAssertNil(SubscriptionAccessBlock.evaluate(status: nil, expiresAt: nil, at: now))
    }

    func test_accountExpiredIncludesEqualityAtDeadline() {
        let account = ProviderAccount(
            username: "fixture", expiresAt: now, isTrial: false,
            maxConnections: 1, activeConnections: 0
        )
        XCTAssertTrue(account.isExpired(at: now))
        XCTAssertEqual(account.subscriptionBlock(at: now)?.status, .expired)
        XCTAssertFalse(account.isExpired(at: now.addingTimeInterval(-1)))
    }

    func test_legacyCodableAccountsAndSourcesKeepUnknownStatus() throws {
        let playlist = Playlist(id: "p", name: "Source", kind: .sampleLibrary, createdAt: now)
        let account = ProviderAccount(
            username: "fixture", expiresAt: nil, isTrial: false,
            maxConnections: 1, activeConnections: 0
        )
        let restoredPlaylist = try JSONDecoder().decode(Playlist.self, from: JSONEncoder().encode(playlist))
        let restoredAccount = try JSONDecoder().decode(ProviderAccount.self, from: JSONEncoder().encode(account))
        XCTAssertNil(restoredPlaylist.subscriptionStatus)
        XCTAssertNil(restoredPlaylist.subscriptionBlock(at: now))
        XCTAssertNil(restoredAccount.subscriptionStatus)
        XCTAssertNil(restoredAccount.subscriptionBlock(at: now))
    }
}
