import XCTest
import OctopusDomain
@testable import Octopus

@MainActor
final class PlaylistSubscriptionMonitorTests: XCTestCase {
    func test_localDeadlineBlocksAtExactBoundaryWithoutRemoteRequest() async throws {
        let clock = SubscriptionTestClock()
        let deadline = clock.date.addingTimeInterval(10)
        let playlist = try makePlaylist(expiresAt: deadline)
        let repository = SubscriptionTestRepository([playlist])
        let validator = SubscriptionTestValidator(.success(account(expiresAt: deadline)))
        let sleeper = SubscriptionTestSleep()
        let waiting = expectation(description: "Timer waits for the exact local deadline")
        let blocked = expectation(description: "Deadline blocks locally")
        sleeper.onEntry = { waiting.fulfill() }
        var didBlock = false
        let monitor = makeMonitor(repository, validator, clock, sleep: sleeper.wait) { state in
            if state.block != nil, !didBlock { didBlock = true; blocked.fulfill() }
        }
        defer { monitor.select(nil); sleeper.cancel() }
        monitor.select(playlist)
        XCTAssertNil(monitor.state.block)
        await fulfillment(of: [waiting], timeout: 2)
        XCTAssertEqual(sleeper.intervals.first, 10)

        clock.date = deadline
        sleeper.advance()
        await fulfillment(of: [blocked], timeout: 2)

        XCTAssertEqual(monitor.state.block, SubscriptionAccessBlock(status: .expired, expiresAt: deadline))
        XCTAssertTrue(validator.calls.isEmpty)
        XCTAssertEqual(repository.subscriptionWrites, 0)
    }

    func test_confirmedRenewalClearsExpiredBlockAndPersistsBothAccountFields() async throws {
        let clock = SubscriptionTestClock()
        let playlist = try makePlaylist(expiresAt: clock.date.addingTimeInterval(-1))
        let renewedDeadline = clock.date.addingTimeInterval(3600)
        let repository = SubscriptionTestRepository([playlist])
        let validator = SubscriptionTestValidator(.success(account(expiresAt: renewedDeadline)))
        let monitor = makeMonitor(repository, validator, clock)
        defer { monitor.select(nil) }
        monitor.select(playlist)
        XCTAssertEqual(monitor.state.block?.status, .expired)

        await monitor.refresh(force: true)

        XCTAssertNil(monitor.state.block)
        XCTAssertNil(monitor.state.error)
        XCTAssertFalse(monitor.state.isChecking)
        XCTAssertEqual(repository.records[playlist.id]?.subscriptionStatus, .active)
        XCTAssertEqual(repository.records[playlist.id]?.expiresAt, renewedDeadline)
        XCTAssertEqual(repository.subscriptionWrites, 1)
    }

    func test_knownDeadlineStillBlocksWhenLocalStorageReadFails() async throws {
        let clock = SubscriptionTestClock()
        let deadline = clock.date.addingTimeInterval(10)
        let playlist = try makePlaylist(expiresAt: deadline)
        let repository = SubscriptionTestRepository([playlist])
        let validator = SubscriptionTestValidator(.success(account(expiresAt: deadline)))
        let monitor = makeMonitor(repository, validator, clock)
        defer { monitor.select(nil) }
        monitor.select(playlist)
        XCTAssertNil(monitor.state.block)

        clock.date = deadline
        repository.readError = .storage(reason: "fixture read failure")
        await monitor.reloadLocal()

        XCTAssertEqual(monitor.state.block, SubscriptionAccessBlock(status: .expired, expiresAt: deadline))
        XCTAssertTrue(validator.calls.isEmpty)
        XCTAssertEqual(repository.subscriptionWrites, 0)
    }

    func test_networkFailureKeepsCachedExpiredBlockWithoutWritingAccountStatus() async throws {
        let clock = SubscriptionTestClock()
        let playlist = try makePlaylist(expiresAt: clock.date.addingTimeInterval(-1))
        let repository = SubscriptionTestRepository([playlist])
        let error = AppError.network(reason: "fixture timeout")
        let validator = SubscriptionTestValidator(.failure(error))
        let monitor = makeMonitor(repository, validator, clock)
        defer { monitor.select(nil) }
        monitor.select(playlist)
        let cachedBlock = monitor.state.block

        await monitor.refresh(force: true)

        XCTAssertEqual(monitor.state.block, cachedBlock)
        XCTAssertEqual(monitor.state.error, error)
        XCTAssertFalse(monitor.state.isChecking)
        XCTAssertEqual(repository.subscriptionWrites, 0)
        XCTAssertEqual(repository.records[playlist.id], playlist)
    }

    func test_cancelledOldSourceResponseCannotBlockOrPersistIntoNewSelection() async throws {
        let clock = SubscriptionTestClock()
        let first = try makePlaylist(id: "first", expiresAt: clock.date.addingTimeInterval(3600))
        let second = try makePlaylist(id: "second", expiresAt: clock.date.addingTimeInterval(7200))
        let repository = SubscriptionTestRepository([first, second])
        let denial = SubscriptionAccessBlock(status: .banned, expiresAt: nil)
        let validator = SubscriptionTestValidator(.failure(.subscriptionUnavailable(denial)))
        validator.suspends = true
        let entered = expectation(description: "First source request is suspended")
        validator.onEntry = { entered.fulfill() }
        let monitor = makeMonitor(repository, validator, clock)
        defer { monitor.select(nil) }
        monitor.select(first)
        let request = Task { await monitor.refresh(force: true) }
        await fulfillment(of: [entered], timeout: 2)

        monitor.select(second)
        validator.complete(.failure(.subscriptionUnavailable(denial)))
        await request.value

        XCTAssertEqual(monitor.state.playlistID, second.id)
        XCTAssertEqual(monitor.state.playlistName, second.name)
        XCTAssertNil(monitor.state.block)
        XCTAssertNil(monitor.state.error)
        XCTAssertFalse(monitor.state.isChecking)
        XCTAssertEqual(repository.subscriptionWrites, 0)
        XCTAssertEqual(repository.records[first.id], first)
        XCTAssertEqual(repository.records[second.id], second)
    }

    func test_overlappingForcedChecksShareOneSuspendedRequest() async throws {
        let clock = SubscriptionTestClock()
        let playlist = try makePlaylist(expiresAt: clock.date.addingTimeInterval(3600))
        let repository = SubscriptionTestRepository([playlist])
        let response = account(expiresAt: playlist.expiresAt)
        let validator = SubscriptionTestValidator(.success(response))
        validator.suspends = true
        let entered = expectation(description: "Shared remote request entered")
        validator.onEntry = { entered.fulfill() }
        let monitor = makeMonitor(repository, validator, clock)
        defer { monitor.select(nil) }
        monitor.select(playlist)
        let first = Task { await monitor.refresh(force: true) }
        await fulfillment(of: [entered], timeout: 2)
        let secondStarted = expectation(description: "Second caller joins the active request")
        let second = Task {
            secondStarted.fulfill()
            await monitor.refresh(force: true)
        }
        await fulfillment(of: [secondStarted], timeout: 2)
        XCTAssertEqual(validator.calls, [playlist.id])
        XCTAssertTrue(monitor.state.isChecking)

        validator.complete(.success(response))
        await first.value
        await second.value

        XCTAssertEqual(validator.calls, [playlist.id])
        XCTAssertEqual(repository.subscriptionWrites, 1)
        XCTAssertFalse(monitor.state.isChecking)
    }

    func test_confirmedDenialSurvivesStorageFailureAndLocalReload() async throws {
        let clock = SubscriptionTestClock()
        let playlist = try makePlaylist(expiresAt: clock.date.addingTimeInterval(3600))
        let repository = SubscriptionTestRepository([playlist])
        let storageError = AppError.storage(reason: "fixture write failure")
        repository.subscriptionWriteError = storageError
        let denial = SubscriptionAccessBlock(status: .disabled, expiresAt: nil)
        let validator = SubscriptionTestValidator(.failure(.subscriptionUnavailable(denial)))
        let monitor = makeMonitor(repository, validator, clock)
        defer { monitor.select(nil) }
        monitor.select(playlist)
        XCTAssertNil(monitor.state.block)

        await monitor.refresh(force: true)
        await monitor.reloadLocal()
        monitor.select(playlist)

        XCTAssertEqual(monitor.state.block, denial)
        XCTAssertEqual(monitor.state.error, storageError)
        XCTAssertFalse(monitor.state.isChecking)
        XCTAssertEqual(repository.records[playlist.id], playlist)
        XCTAssertEqual(repository.subscriptionWrites, 1)
    }

    func test_foregroundChecksRespectFiveMinuteCooldownWhileExplicitRetryBypassesIt() async throws {
        let clock = SubscriptionTestClock()
        let playlist = try makePlaylist(expiresAt: clock.date.addingTimeInterval(3600))
        let repository = SubscriptionTestRepository([playlist])
        let validator = SubscriptionTestValidator(.success(account(expiresAt: playlist.expiresAt)))
        let monitor = makeMonitor(repository, validator, clock)
        defer { monitor.select(nil) }
        monitor.select(playlist)
        await monitor.refresh()

        clock.date = clock.date.addingTimeInterval(299)
        await monitor.refresh()
        XCTAssertEqual(validator.calls.count, 1)
        clock.date = clock.date.addingTimeInterval(1)
        await monitor.refresh()
        XCTAssertEqual(validator.calls.count, 2)
        await monitor.refresh(force: true)
        XCTAssertEqual(validator.calls.count, 3)
        XCTAssertNil(monitor.state.block)
    }

    private func makePlaylist(id: Playlist.ID = "fixture", expiresAt: Date?) throws -> Playlist {
        Playlist(
            id: id, name: "Fixture \(id.value)",
            kind: .xtream(host: try XCTUnwrap(URL(string: "https://example.invalid")), username: "fixture"),
            createdAt: Date(timeIntervalSince1970: 0), isActive: true,
            expiresAt: expiresAt, subscriptionStatus: .active
        )
    }

    private func account(expiresAt: Date?) -> ProviderAccount {
        ProviderAccount(username: "fixture", expiresAt: expiresAt, isTrial: false,
                        maxConnections: 1, activeConnections: 0, subscriptionStatus: .active)
    }

    private func makeMonitor(
        _ repository: SubscriptionTestRepository, _ validator: SubscriptionTestValidator,
        _ clock: SubscriptionTestClock,
        sleep: @escaping (TimeInterval) async throws -> Void = { _ in throw CancellationError() },
        onChange: @escaping (PlaylistSubscriptionMonitor.State) -> Void = { _ in }
    ) -> PlaylistSubscriptionMonitor {
        PlaylistSubscriptionMonitor(
            playlists: repository, validator: validator, password: { _ in nil },
            now: { clock.date }, sleep: sleep, onChange: onChange
        )
    }
}
