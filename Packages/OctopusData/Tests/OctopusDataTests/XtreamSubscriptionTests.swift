import XCTest
import OctopusDomain
@testable import OctopusData

final class XtreamSubscriptionTests: XCTestCase {
    private let instant: TimeInterval = 2_000_000_000

    private func provider(status: String, expiration: Int?) throws -> XtreamContentProvider {
        let expiry = expiration.map(String.init) ?? ""
        let data = Data("""
        {"user_info":{"auth":1,"status":"\(status)","exp_date":"\(expiry)"}}
        """.utf8)
        let date = Date(timeIntervalSince1970: instant)
        return XtreamContentProvider(
            baseURL: try XCTUnwrap(URL(string: "https://provider.example")),
            username: "fixture", password: "fixture", playlistID: "p",
            httpClient: StubHTTPClient { _ in data }, now: { date }
        )
    }

    func test_activeProviderAtOrPastDeadlineRejectsBeforeCatalogAccess() async throws {
        for expiry in [Int(instant) - 1, Int(instant)] {
            do {
                _ = try await provider(status: "Active", expiration: expiry).authenticate()
                XCTFail("Expired account must not authenticate")
            } catch {
                XCTAssertEqual(error as? AppError, .subscriptionUnavailable(
                    SubscriptionAccessBlock(status: .expired, expiresAt: Date(timeIntervalSince1970: Double(expiry)))
                ))
            }
        }
        let account = try await provider(status: "Active", expiration: Int(instant) + 1).authenticate()
        XCTAssertEqual(account.subscriptionStatus, .active)
    }

    func test_explicitUnavailableStatusesBlockWithoutDate() async throws {
        for status in [SubscriptionStatus.expired, .inactive, .banned, .disabled] {
            do {
                _ = try await provider(status: status.rawValue.uppercased(), expiration: nil).authenticate()
                XCTFail("Unavailable status must be rejected")
            } catch {
                XCTAssertEqual(error as? AppError, .subscriptionUnavailable(
                    SubscriptionAccessBlock(status: status, expiresAt: nil)
                ))
            }
        }
    }

    func test_unknownStatusIsNotDeclaredActiveAndUnlimitedActiveStillWorks() async throws {
        do {
            _ = try await provider(status: "unknown", expiration: nil).authenticate()
            XCTFail("Unknown status must not establish access")
        } catch {
            XCTAssertEqual(error as? AppError, .unauthorized)
        }
        let account = try await provider(status: "Active", expiration: 0).authenticate()
        XCTAssertNil(account.expiresAt)
    }

    func test_newSourceValidationUsesSameInjectedDeadline() async throws {
        let date = Date(timeIntervalSince1970: instant)
        let data = Data("""
        {"user_info":{"auth":1,"status":"Active","exp_date":"2000000000"}}
        """.utf8)
        let validator = ProviderValidator(httpClient: StubHTTPClient { _ in data }, now: { date })
        let playlist = Playlist(
            id: "p", name: "Source", kind: .xtream(
                host: try XCTUnwrap(URL(string: "https://provider.example")), username: "fixture"
            ), createdAt: date
        )
        do {
            _ = try await validator.validate(playlist, password: "fixture")
            XCTFail("Source must not be saved at the exact expiration instant")
        } catch {
            XCTAssertEqual(error as? AppError, .subscriptionUnavailable(
                SubscriptionAccessBlock(status: .expired, expiresAt: date)
            ))
        }
    }
}
