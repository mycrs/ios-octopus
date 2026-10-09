import Foundation
import XCTest
import OctopusDomain

@MainActor
final class SubscriptionTestClock {
    var date = Date(timeIntervalSince1970: 1_800_000_000)
}

@MainActor
final class SubscriptionTestRepository: PlaylistRepository {
    var records: [Playlist.ID: Playlist]
    var readError: AppError?
    var subscriptionWriteError: AppError?
    private(set) var subscriptionWrites = 0

    init(_ playlists: [Playlist]) {
        records = Dictionary(uniqueKeysWithValues: playlists.map { ($0.id, $0) })
    }

    func all() async throws -> [Playlist] { Array(records.values) }
    func playlist(id: Playlist.ID) async throws -> Playlist? {
        if let readError { throw readError }
        return records[id]
    }
    func activePlaylist() async throws -> Playlist? { records.values.first { $0.isActive } }
    func add(_ playlist: Playlist, password: String?) async throws { records[playlist.id] = playlist }
    func update(_ playlist: Playlist) async throws { records[playlist.id] = playlist }
    func delete(id: Playlist.ID) async throws { records[id] = nil }
    func setActive(id: Playlist.ID) async throws {
        for key in records.keys { records[key]?.isActive = key == id }
    }
    func updateSubscription(id: Playlist.ID, status: SubscriptionStatus?, expiresAt: Date?) async throws {
        subscriptionWrites += 1
        if let subscriptionWriteError { throw subscriptionWriteError }
        guard var playlist = records[id] else { throw AppError.notFound }
        playlist.subscriptionStatus = status
        playlist.expiresAt = expiresAt
        records[id] = playlist
    }
}

@MainActor
final class SubscriptionTestValidator: PlaylistValidating {
    var result: Result<ProviderAccount, AppError>
    var suspends = false
    var onEntry: (() -> Void)?
    private var pending: [CheckedContinuation<ProviderAccount, Error>] = []
    private var completedResult: Result<ProviderAccount, AppError>?
    private(set) var calls: [Playlist.ID] = []

    init(_ result: Result<ProviderAccount, AppError>) { self.result = result }

    func validate(_ playlist: Playlist, password: String?) async throws -> ProviderAccount {
        calls.append(playlist.id)
        if !suspends { onEntry?(); return try result.get() }
        if let completedResult { onEntry?(); return try completedResult.get() }
        return try await withCheckedThrowingContinuation { continuation in
            pending.append(continuation)
            onEntry?()
        }
    }

    func complete(_ result: Result<ProviderAccount, AppError>) {
        completedResult = result
        let continuations = pending
        pending.removeAll()
        for continuation in continuations {
            continuation.resume(with: result.mapError { $0 as Error })
        }
    }
}

@MainActor
final class SubscriptionTestSleep {
    var onEntry: (() -> Void)?
    private(set) var intervals: [TimeInterval] = []
    private var pending: CheckedContinuation<Void, Error>?
    private var released = false

    func wait(_ interval: TimeInterval) async throws {
        intervals.append(interval)
        guard !released else { throw CancellationError() }
        try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            onEntry?()
        }
    }

    func advance() {
        released = true
        let continuation = pending
        pending = nil
        continuation?.resume()
    }

    func cancel() {
        released = true
        let continuation = pending
        pending = nil
        continuation?.resume(throwing: CancellationError())
    }
}
