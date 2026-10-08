import UIKit

/// Fullscreen orientation belongs to a window scene, not the whole application.
/// A nested presentation cannot release another player's landscape restriction.
@MainActor
final class PlayerOrientationPolicy {
    static let shared = PlayerOrientationPolicy()

    private struct Scope {
        let originalOrientation: UIInterfaceOrientation
        var leases: Set<UUID>
    }
    private var scenes: [ObjectIdentifier: Scope] = [:]

    func acquire(sceneID: ObjectIdentifier, orientation: UIInterfaceOrientation) -> UUID {
        let lease = UUID()
        if var scope = scenes[sceneID] {
            scope.leases.insert(lease)
            scenes[sceneID] = scope
        } else {
            scenes[sceneID] = Scope(originalOrientation: orientation, leases: [lease])
        }
        return lease
    }

    /// Returns the previous orientation only when the final valid lease ends.
    func release(sceneID: ObjectIdentifier, lease: UUID) -> UIInterfaceOrientation? {
        guard var scope = scenes[sceneID], scope.leases.remove(lease) != nil else { return nil }
        guard scope.leases.isEmpty else {
            scenes[sceneID] = scope
            return nil
        }
        scenes.removeValue(forKey: sceneID)
        return scope.originalOrientation
    }

    func supportsLandscapeOnly(sceneID: ObjectIdentifier) -> Bool {
        scenes[sceneID] != nil
    }

    func supportedOrientations(sceneID: ObjectIdentifier?, isPad: Bool) -> UIInterfaceOrientationMask {
        if let sceneID, supportsLandscapeOnly(sceneID: sceneID) { return .landscape }
        return isPad ? .all : .allButUpsideDown
    }
}

@MainActor
final class OctopusAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        PlayerOrientationPolicy.shared.supportedOrientations(
            sceneID: window?.windowScene.map(ObjectIdentifier.init),
            isPad: window?.traitCollection.userInterfaceIdiom == .pad
                || (window == nil && UIDevice.current.userInterfaceIdiom == .pad)
        )
    }
}
