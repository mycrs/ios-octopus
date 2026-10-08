import SwiftUI
import UIKit
import OctopusNavigation

/// This bridge presents an owned UIKit controller, rather than putting a
/// rotation controller inside SwiftUI's already-presented fullscreen cover.
struct PlayerFullscreenPresenter: UIViewControllerRepresentable {
    let presentation: PlayerPresentation?
    let reconciliationRevision: Int
    let makeContent: @MainActor (PlayerPresentation) -> AnyView
    let onDismiss: @MainActor (String) -> Void

    init(presentation: PlayerPresentation?, reconciliationRevision: Int = 0,
         makeContent: @escaping @MainActor (PlayerPresentation) -> AnyView,
         onDismiss: @escaping @MainActor (String) -> Void) {
        self.presentation = presentation
        self.reconciliationRevision = reconciliationRevision
        self.makeContent = makeContent
        self.onDismiss = onDismiss
    }

    func makeUIViewController(context: Context) -> PlayerFullscreenPresenterController {
        PlayerFullscreenPresenterController()
    }

    func updateUIViewController(_ controller: PlayerFullscreenPresenterController, context: Context) {
        let content: AnyView?
        if let presentation { content = makeContent(presentation) }
        else { content = nil }
        controller.update(
            id: presentation?.id, content: content, onDismiss: onDismiss
        )
    }

    static func dismantleUIViewController(_ controller: PlayerFullscreenPresenterController, coordinator: ()) {
        controller.invalidate()
    }
}

/// Serializes UIKit transitions; late completions may not dismiss a newer ID.
struct PlayerFullscreenPresentationState {
    enum Action: Equatable { case present(String), update(String), dismiss(String) }
    private(set) var desiredID: String?
    private(set) var displayedID: String?
    private var transition: Action?
    var transitioningID: String? {
        switch transition {
        case .present(let id), .dismiss(let id): return id
        default: return nil
        }
    }

    mutating func request(_ id: String?) { desiredID = id }
    mutating func nextAction() -> Action? {
        guard transition == nil else { return nil }
        if let displayedID {
            if displayedID == desiredID { return .update(displayedID) }
            transition = .dismiss(displayedID)
            return .dismiss(displayedID)
        }
        guard let desiredID else { return nil }
        displayedID = desiredID
        transition = .present(desiredID)
        return .present(desiredID)
    }
    mutating func didPresent(_ id: String) {
        guard displayedID == id, transition == .present(id) else { return }
        transition = nil
    }
    mutating func didDismiss(_ id: String) {
        guard displayedID == id else { return }
        displayedID = nil
        transition = nil
    }
}

@MainActor
final class PlayerFullscreenPresenterController: UIViewController, UIAdaptivePresentationControllerDelegate {
    private var state = PlayerFullscreenPresentationState()
    private var content: AnyView?
    private var host: LandscapePlayerHostingController?
    private var retiringHost: LandscapePlayerHostingController?
    private var onDismiss: (@MainActor (String) -> Void)?
    private var invalidated = false
    private var mayDeferReconciliation = false

    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        reconcile()
    }
    func update(id: String?, content: AnyView?, onDismiss: @escaping @MainActor (String) -> Void) {
        guard !invalidated else { return }
        state.request(id)
        if id == nil { releaseRetiringOrientation() }
        self.content = content
        self.onDismiss = onDismiss
        mayDeferReconciliation = true
        reconcile()
    }
    private func reconcile() {
        guard !invalidated, let window = viewIfLoaded?.window, let scene = window.windowScene else { return }
        var anchor: UIViewController = self
        while let parent = anchor.parent { anchor = parent }
        if let presented = anchor.presentedViewController, presented !== host {
            // Wait for someone else's sheet to finish; never dismiss it here.
            if presented.isBeingDismissed, let transition = presented.transitionCoordinator {
                transition.animate(alongsideTransition: nil) { [weak self] _ in self?.reconcile() }
            } else if mayDeferReconciliation {
                // SwiftUI may update this bridge before it starts dismissing
                // its sheet. Inspect the next turn once, then use its transition.
                mayDeferReconciliation = false
                DispatchQueue.main.async { [weak self] in self?.reconcile() }
            }
            return
        }
        guard let action = state.nextAction() else { return }
        switch action {
        case .update(let id):
            if host?.playerID == id, let content { host?.rootView = content }
        case .present(let id):
            guard let content else { state.didDismiss(id); return }
            let controller = LandscapePlayerHostingController(
                playerID: id, content: content, window: window, scene: scene
            )
            host = controller
            releaseRetiringOrientation()
            controller.presentationController?.delegate = self
            // Retain the bridge until UIKit completes even if SwiftUI dismantles
            // it mid-transition; that completion must still dismiss its host.
            anchor.present(controller, animated: true) { [self, controller] in
                guard self.host === controller else { return }
                self.state.didPresent(id)
                controller.presentationController?.delegate = self
                if self.invalidated { self.dismissOwned(controller, animated: false) }
                else { self.reconcile() }
            }
        case .dismiss:
            if let host { dismissOwned(host, animated: true) }
        }
    }
    private func dismissOwned(_ controller: LandscapePlayerHostingController, animated: Bool) {
        guard host === controller else { return }
        guard controller.presentingViewController != nil else { completeDismissal(controller); return }
        controller.dismiss(animated: animated) { [self, controller] in
            completeDismissal(controller)
        }
    }
    private func completeDismissal(_ controller: LandscapePlayerHostingController) {
        guard host === controller else { return }
        host = nil
        state.didDismiss(controller.playerID)
        if state.desiredID == controller.playerID { state.request(nil); content = nil }
        // Retain the original scene baseline until a queued replacement owns
        // its lease, even if another sheet temporarily blocks presentation.
        retiringHost = controller
        onDismiss?(controller.playerID)
        reconcile()
        if state.desiredID == nil || invalidated { releaseRetiringOrientation() }
    }
    private func releaseRetiringOrientation() {
        retiringHost?.releaseOrientationAfterDismissal()
        retiringHost = nil
    }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard let controller = presentationController.presentedViewController as? LandscapePlayerHostingController
        else { return }
        completeDismissal(controller)
    }
    func invalidate() {
        guard !invalidated else { return }
        invalidated = true
        state.request(nil)
        content = nil
        releaseRetiringOrientation()
        guard let host else { return }
        onDismiss?(host.playerID)
        onDismiss = nil
        // A presentation completion handles teardown if UIKit is still opening.
        guard !host.isBeingPresented else { return }
        dismissOwned(host, animated: false)
    }
}
