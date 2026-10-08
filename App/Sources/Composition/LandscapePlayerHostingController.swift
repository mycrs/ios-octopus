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
    private var orientationLock = PlayerFullscreenOrientationLockState()

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .landscapeRight }

    @available(iOS 26.0, *)
    override var prefersInterfaceOrientationLocked: Bool { lease != nil && orientationLock.prefersLocked }

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

    /// UIKit calls viewDidAppear before its presentation completion. Request
    /// geometry only once the owned presentation has actually committed.
    func presentationDidComplete() {
        guard let scene = playerScene, lease != nil, !orientationLock.isClosing,
              presentingViewController != nil, !isBeingDismissed else { return }
        setNeedsUpdateOfSupportedInterfaceOrientations()
        Self.request(.landscape, scene: scene, window: playerWindow)
        orientationLock.didRequestLandscape()
        updateOrientationLockIfAligned()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateOrientationLockIfAligned()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.updateOrientationLockIfAligned()
        }
    }

    private func updateOrientationLockIfAligned() {
        guard lease != nil, let scene = playerScene, let window = viewIfLoaded?.window,
              window.windowScene === scene,
              orientationLock.observe(
                orientation: scene.interfaceOrientation, viewSize: view.bounds.size,
                windowSize: window.bounds.size
              ) else { return }
        if #available(iOS 26.0, *) { setNeedsUpdateOfPrefersInterfaceOrientationLocked() }
    }

    /// Drop the visible controller's lock preference before UIKit dismisses it.
    /// Keep its scene lease and supported mask until actual dismissal completes.
    func prepareForDismissal() {
        guard orientationLock.beginDismissal() else { return }
        if #available(iOS 26.0, *) { setNeedsUpdateOfPrefersInterfaceOrientationLocked() }
    }

    func recordDismissalDiagnostics() {
        PlayerDismissalDiagnostics.schedule(window: playerWindow)
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
        let locked: Int
        if #available(iOS 26.0, *) {
            locked = scene.effectiveGeometry.isInterfaceOrientationLocked ? 1 : 0
        } else {
            locked = -1
        }
        // UIApplication's getter describes the Info.plist default, not the
        // app delegate's scene-scoped override. Record those separately.
        let defaultAppMask = UIApplication.shared.supportedInterfaceOrientations(for: window).rawValue
        let policyMask = PlayerOrientationPolicy.shared.supportedOrientations(
            sceneID: ObjectIdentifier(scene), isPad: scene.traitCollection.userInterfaceIdiom == .pad
        ).rawValue
        let rootMask = window?.rootViewController?.supportedInterfaceOrientations.rawValue ?? 0
        let presented = window?.rootViewController?.presentedViewController
        let presentedMask = presented?.supportedInterfaceOrientations.rawValue ?? 0
        let beingPresented = presented?.isBeingPresented == true ? 1 : 0
        let coordinator = presented?.transitionCoordinator == nil ? 0 : 1
        let width = Double(window?.bounds.width ?? 0)
        let height = Double(window?.bounds.height ?? 0)
        Log.ui.info("Player orientation request state requested=\(mask.rawValue, privacy: .public) orientation=\(scene.interfaceOrientation.rawValue, privacy: .public) locked=\(locked, privacy: .public) defaultAppMask=\(defaultAppMask, privacy: .public) policyMask=\(policyMask, privacy: .public) rootMask=\(rootMask, privacy: .public) presentedMask=\(presentedMask, privacy: .public) beingPresented=\(beingPresented, privacy: .public) coordinator=\(coordinator, privacy: .public) width=\(width, privacy: .public) height=\(height, privacy: .public)")
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
            Log.ui.error("Player orientation request failed; code=\((error as NSError).code, privacy: .public)")
            let supported = PlayerOrientationRequestDiagnostics.deniedMask(in: error.localizedDescription)
                .map { Int($0.rawValue) } ?? -1
            Log.ui.error("Player orientation rejection state code=\((error as NSError).code, privacy: .public) reportedSupported=\(supported, privacy: .public)")
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
