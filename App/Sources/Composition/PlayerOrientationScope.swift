import SwiftUI
import UIKit
import OctopusCore

/// Uses iOS 16's public scene geometry API; no device KVC or global orientation lock.
struct PlayerOrientationScope: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> PlayerOrientationController {
        PlayerOrientationController()
    }

    func updateUIViewController(_ controller: PlayerOrientationController, context: Context) {}

    static func dismantleUIViewController(_ controller: PlayerOrientationController, coordinator: ()) {
        controller.releaseOrientation()
    }
}

@MainActor
final class PlayerOrientationController: UIViewController {
    private weak var playerScene: UIWindowScene?
    private weak var playerWindow: UIWindow?
    private var playerSceneID: ObjectIdentifier?
    private var lease: UUID?
    private var originalOrientation: UIInterfaceOrientation?

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        lease == nil ? (traitCollection.userInterfaceIdiom == .pad ? .all : .allButUpsideDown) : .landscape
    }

    override func loadView() {
        view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard lease == nil, let window = view.window, let scene = window.windowScene else { return }
        playerScene = scene
        playerWindow = window
        playerSceneID = ObjectIdentifier(scene)
        lease = PlayerOrientationPolicy.shared.acquire(
            sceneID: ObjectIdentifier(scene), orientation: originalOrientation ?? scene.interfaceOrientation
        )
        setNeedsUpdateOfSupportedInterfaceOrientations()
        Self.request(.landscape, scene: scene, window: window)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if lease == nil, originalOrientation == nil {
            originalOrientation = view.window?.windowScene?.interfaceOrientation
        }
    }

    func releaseOrientation() {
        guard let sceneID = playerSceneID, let lease else { return }
        self.lease = nil
        playerSceneID = nil
        setNeedsUpdateOfSupportedInterfaceOrientations()
        let previous = PlayerOrientationPolicy.shared.release(sceneID: sceneID, lease: lease)
        guard let previous, let scene = playerScene else { return }
        let restore = { [weak scene, weak window = playerWindow] in
            guard let scene,
                  !PlayerOrientationPolicy.shared.supportsLandscapeOnly(sceneID: ObjectIdentifier(scene))
            else { return }
            Self.request(Self.mask(for: previous), scene: scene, window: window)
        }
        // Wait for the cover's UIKit dismissal before asking its presenter to rotate.
        if let transition = playerWindow?.rootViewController?.presentedViewController?.transitionCoordinator {
            if transition.animate(alongsideTransition: nil, completion: { _ in restore() }) { return }
        }
        DispatchQueue.main.async(execute: restore)
    }

    private static func mask(for orientation: UIInterfaceOrientation) -> UIInterfaceOrientationMask {
        switch orientation {
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        case .portraitUpsideDown: return .portraitUpsideDown
        default: return .portrait
        }
    }

    private static func request(_ mask: UIInterfaceOrientationMask, scene: UIWindowScene, window: UIWindow?) {
        if let root = window?.rootViewController { updateSupportedOrientations(root) }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
            Log.ui.error("Player orientation request failed; code=\((error as NSError).code, privacy: .public)")
        }
    }

    private static func updateSupportedOrientations(_ controller: UIViewController) {
        controller.setNeedsUpdateOfSupportedInterfaceOrientations()
        controller.children.forEach(updateSupportedOrientations)
        if let presented = controller.presentedViewController { updateSupportedOrientations(presented) }
    }
}
