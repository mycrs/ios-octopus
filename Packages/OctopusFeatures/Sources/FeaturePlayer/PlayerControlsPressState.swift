import Foundation

/// Per-screen timer bookkeeping; accessed by the player's UI callbacks.
/// This reference deliberately publishes no changes: disappearing controls
/// must not invalidate the hosted overlay again while it is being replaced.
final class PlayerControlsPressState {
    private var active: Set<UUID> = []

    var isPressed: Bool { !active.isEmpty }

    func begin(_ id: UUID) {
        active.insert(id)
    }

    /// Only the final known release may restart the inactivity timer.
    func end(_ id: UUID) -> Bool {
        guard active.remove(id) != nil else { return false }
        return active.isEmpty
    }
}
