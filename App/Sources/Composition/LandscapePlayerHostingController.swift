import SwiftUI
import UIKit
import OctopusCore

/// The controller actually presented fullscreen owns the rotation preference.
@MainActor
final class LandscapePlayerHostingController: UIHostingController<AnyView> {
    let playerID: String
    private weak var playerScene: UIWindowScene?
    private weak var playerWindow: UIWindow?
    private let sceneID: ObjectIdentifier
    private var lease: UUID?

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .landscapeRight }

    @available(iOS 26.0, *)
    override var prefersInterfaceOrientationLocked: Bool { lease != nil }

    init(playerID: String, content: AnyView, window: UIWindow, scene: UIWindowScene) {
        self.playerID = playerID
        self.playerScene = scene
        self.playerWindow = window
        self.sceneID = ObjectIdentifier(scene)
        // Presentation can rotate before viewDidAppear: capture and lease now.
        self.lease = PlayerOrientationPolicy.shared.acquire(
            sceneID: ObjectIdentifier(scene), orientation: scene.interfaceOrientation
        )
        super.init(rootView: content)
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .crossDissolve
        isModalInPresentation = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let scene = playerScene, lease != nil else { return }
        setNeedsUpdateOfSupportedInterfaceOrientations()
        if #available(iOS 26.0, *) { setNeedsUpdateOfPrefersInterfaceOrientationLocked() }
        Self.request(.landscape, scene: scene, window: playerWindow)
    }

    /// Call only after actual dismissal. Another player's lease wins over this
    /// restoration, including a presentation starting in the same transition.
    func releaseOrientationAfterDismissal() {
        guard let lease else { return }
        self.lease = nil
        let previous = PlayerOrientationPolicy.shared.release(sceneID: sceneID, lease: lease)
        guard let previous, let scene = playerScene else { return }
        if #available(iOS 26.0, *) { setNeedsUpdateOfPrefersInterfaceOrientationLocked() }
        let sceneID = sceneID
        // A queued replacement can acquire its lease in dismissal completion.
        // Check again after that callback before issuing the restore request.
        DispatchQueue.main.async { [weak scene, weak window = playerWindow] in
            guard let scene,
                  !PlayerOrientationPolicy.shared.supportsLandscapeOnly(sceneID: sceneID) else { return }
            Self.request(Self.mask(for: previous), scene: scene, window: window)
        }
    }

    private static func request(_ mask: UIInterfaceOrientationMask, scene: UIWindowScene, window: UIWindow?) {
        if let root = window?.rootViewController { updateOrientations(root) }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
            Log.ui.error("Player orientation request failed; code=\((error as NSError).code, privacy: .public)")
        }
    }

    private static func updateOrientations(_ controller: UIViewController) {
        controller.setNeedsUpdateOfSupportedInterfaceOrientations()
        if #available(iOS 26.0, *) { controller.setNeedsUpdateOfPrefersInterfaceOrientationLocked() }
        controller.children.forEach(updateOrientations)
        if let presented = controller.presentedViewController { updateOrientations(presented) }
    }

    private static func mask(for orientation: UIInterfaceOrientation) -> UIInterfaceOrientationMask {
        switch orientation {
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        case .portraitUpsideDown: return .portraitUpsideDown
        default: return .portrait
        }
    }
}
