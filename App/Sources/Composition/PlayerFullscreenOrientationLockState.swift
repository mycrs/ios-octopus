import UIKit

/// A scene lease limits supported orientations; its visible lock starts only
/// after UIKit has actually reached landscape, otherwise it locks portrait.
struct PlayerFullscreenOrientationLockState {
    private enum Phase { case awaitingRequest, awaitingLandscape, locked, closing }
    private var phase = Phase.awaitingRequest

    var prefersLocked: Bool { phase == .locked }
    var isClosing: Bool { phase == .closing }

    mutating func didRequestLandscape() {
        guard phase == .awaitingRequest else { return }
        phase = .awaitingLandscape
    }

    /// Returns true only when the public lock preference changes.
    mutating func observe(
        orientation: UIInterfaceOrientation, viewSize: CGSize, windowSize: CGSize
    ) -> Bool {
        guard phase == .awaitingLandscape, orientation.isLandscape,
              viewSize.height > 0, viewSize.width > viewSize.height,
              windowSize.height > 0, windowSize.width > windowSize.height else { return false }
        phase = .locked
        return true
    }

    /// Seal before dismissal so a late rotation callback cannot lock again.
    mutating func beginDismissal() -> Bool {
        guard phase != .closing else { return false }
        phase = .closing
        return true
    }
}
