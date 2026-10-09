import Foundation
import OctopusDomain

/// Checks the local deadline without network polling. Foreground checks share
/// one request and a cooldown; a user's explicit retry can recheck a renewal.
@MainActor
final class PlaylistSubscriptionMonitor {
    struct State: Equatable {
        var playlistID: Playlist.ID?
        var playlistName: String?
        var block: SubscriptionAccessBlock?
        var isChecking = false
        var error: AppError?
    }

    private(set) var state = State() {
        didSet { if state != oldValue { onChange(state) } }
    }
    private let playlists: PlaylistRepository
    private let validator: PlaylistValidating
    private let password: (Playlist) throws -> String?
    private let now: () -> Date
    private let sleep: (TimeInterval) async throws -> Void
    private let onChange: (State) -> Void
    private var active: Playlist?
    private var generation = 0
    private var localRevision = 0
    private var lastRemoteCheck: Date?
    private var confirmedBlock: SubscriptionAccessBlock?
    private var localTask: Task<Void, Never>?
    private var remoteTask: Task<Void, Never>?

    init(
        playlists: PlaylistRepository, validator: PlaylistValidating,
        password: @escaping (Playlist) throws -> String?,
        now: @escaping () -> Date = Date.init,
        sleep: @escaping (TimeInterval) async throws -> Void = {
            try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000))
        },
        onChange: @escaping (State) -> Void
    ) {
        self.playlists = playlists
        self.validator = validator
        self.password = password
        self.now = now
        self.sleep = sleep
        self.onChange = onChange
    }

    deinit { localTask?.cancel(); remoteTask?.cancel() }

    func select(_ playlist: Playlist?) {
        let changed = active?.id != playlist?.id
        let deadlineChanged = active?.expiresAt != playlist?.expiresAt
        if changed {
            generation &+= 1
            localTask?.cancel()
            remoteTask?.cancel()
            remoteTask = nil
            lastRemoteCheck = nil
            confirmedBlock = nil
            state = State(playlistID: playlist?.id, playlistName: playlist?.name)
        }
        apply(playlist)
        if changed || deadlineChanged || localTask == nil { scheduleLocalChecks() }
    }

    func reloadLocal() async {
        guard let id = active?.id else { return }
        // The known deadline must still close playback if storage is slow or
        // unavailable. A successful fresh read can then reveal a renewal.
        apply(active)
        let expectedGeneration = generation
        let expectedRevision = localRevision
        // Read only this source. Source switching is owned by AppContainer.
        guard let refreshed = try? await playlists.playlist(id: id),
              generation == expectedGeneration, localRevision == expectedRevision,
              active?.id == id else { return }
        apply(refreshed)
    }

    func refresh(force: Bool = false) async {
        await reloadLocal()
        guard let playlist = active, playlist.kind.isXtream else { return }
        if let remoteTask { await remoteTask.value; return }
        if !force, let lastRemoteCheck,
           now().timeIntervalSince(lastRemoteCheck) >= 0,
           now().timeIntervalSince(lastRemoteCheck) < 300 { return }
        lastRemoteCheck = now()
        let expectedGeneration = generation
        state.isChecking = true
        state.error = nil
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.checkRemote(playlist, generation: expectedGeneration)
        }
        remoteTask = task
        await task.value
        if generation == expectedGeneration { remoteTask = nil }
    }

    private func checkRemote(_ playlist: Playlist, generation expected: Int) async {
        defer { if generation == expected { state.isChecking = false } }
        do {
            let account = try await validator.validate(playlist, password: password(playlist))
            guard generation == expected, !Task.isCancelled else { return }
            try await persist(playlist, status: account.subscriptionStatus,
                              expiresAt: account.expiresAt, generation: expected)
        } catch AppError.subscriptionUnavailable(let block) {
            guard generation == expected, !Task.isCancelled else { return }
            do {
                try await persist(playlist, status: block.status,
                                  expiresAt: block.expiresAt, generation: expected)
            } catch {
                guard generation == expected else { return }
                // A confirmed denial is enforced even if the local write fails.
                confirmedBlock = block
                state.block = block
                state.error = AppError.wrap(error)
            }
        } catch {
            guard generation == expected, !Task.isCancelled else { return }
            // A timeout is not proof that the subscription has expired.
            state.error = AppError.wrap(error)
        }
    }

    private func persist(
        _ playlist: Playlist, status: SubscriptionStatus?, expiresAt: Date?, generation expected: Int
    ) async throws {
        try await playlists.updateSubscription(id: playlist.id, status: status, expiresAt: expiresAt)
        guard generation == expected, active?.id == playlist.id, !Task.isCancelled else { return }
        var updated = active ?? playlist
        updated.subscriptionStatus = status
        updated.expiresAt = expiresAt
        confirmedBlock = nil
        apply(updated)
        scheduleLocalChecks()
        state.error = nil
    }

    private func apply(_ playlist: Playlist?) {
        localRevision &+= 1
        active = playlist
        state.playlistID = playlist?.id
        state.playlistName = playlist?.name
        state.block = confirmedBlock ?? playlist?.subscriptionBlock(at: now())
    }

    private func scheduleLocalChecks() {
        localTask?.cancel()
        guard active != nil else { localTask = nil; return }
        let sleep = sleep
        localTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.nextLocalCheck else { return }
                do { try await sleep(interval) } catch { return }
                guard !Task.isCancelled else { return }
                await self?.reloadLocal()
            }
        }
    }

    private var nextLocalCheck: TimeInterval {
        guard let deadline = active?.expiresAt, deadline > now() else { return 60 }
        return min(60, max(0.1, deadline.timeIntervalSince(now())))
    }
}
