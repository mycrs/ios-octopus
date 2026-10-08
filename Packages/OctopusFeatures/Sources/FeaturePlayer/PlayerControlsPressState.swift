import Foundation

/// Each visible control owns its press, including overlapping touches.
struct PlayerControlsPressState {
    private var active: Set<UUID> = []

    var isPressed: Bool { !active.isEmpty }

    mutating func begin(_ id: UUID) {
        active.insert(id)
    }

    /// Only the final known release may restart the inactivity timer.
    mutating func end(_ id: UUID) -> Bool {
        guard active.remove(id) != nil else { return false }
        return active.isEmpty
    }
}
