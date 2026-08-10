import SwiftUI
import UIKit
import OctopusDesignSystem

/// Kenar kontrollerini VLC'nin EAGL compositor ağacından ayırır.
struct PlayerEdgeWindowPresenter<Content: View>: UIViewRepresentable {
    private let content: Content
    @Environment(\.brandColor) private var brandColor

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    final class Coordinator {
        let store: PlayerHostedOverlayStore<Content>
        let host: PlayerOverlayHostingController<PlayerHostedOverlay<Content>>
        private var overlayWindow: PlayerPassThroughWindow?

        init(content: Content, brandColor: Color) {
            let store = PlayerHostedOverlayStore(
                content: content,
                brandColor: brandColor
            )
            self.store = store
            self.host = PlayerOverlayHostingController(
                rootView: PlayerHostedOverlay(store: store)
            )
            host.view.backgroundColor = .clear
            host.view.isOpaque = false
        }

        func attach(to scene: UIWindowScene) {
            if overlayWindow?.windowScene !== scene {
                hide()
                let window = PlayerPassThroughWindow(windowScene: scene)
                window.backgroundColor = .clear
                window.windowLevel = .normal + 1
                window.rootViewController = host
                overlayWindow = window
            }

            overlayWindow?.frame = scene.coordinateSpace.bounds
            overlayWindow?.isHidden = false
        }

        func hide() {
            overlayWindow?.isHidden = true
            overlayWindow?.rootViewController = nil
            overlayWindow = nil
        }

        deinit { hide() }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(content: content, brandColor: brandColor)
    }

    func makeUIView(context: Context) -> PlayerWindowSceneProbe {
        let probe = PlayerWindowSceneProbe()
        probe.onSceneChange = { [weak coordinator = context.coordinator] scene in
            guard let scene else {
                coordinator?.hide()
                return
            }
            coordinator?.attach(to: scene)
        }
        return probe
    }

    func updateUIView(_ probe: PlayerWindowSceneProbe, context: Context) {
        context.coordinator.store.update(
            content: content,
            brandColor: brandColor
        )
        if let scene = probe.window?.windowScene {
            context.coordinator.attach(to: scene)
        }
    }

    static func dismantleUIView(
        _ probe: PlayerWindowSceneProbe,
        coordinator: Coordinator
    ) {
        probe.onSceneChange = nil
        coordinator.hide()
    }
}

final class PlayerWindowSceneProbe: UIView {
    var onSceneChange: ((UIWindowScene?) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onSceneChange?(window?.windowScene)
    }
}

final class PlayerPassThroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        guard let root = rootViewController else { return nil }
        if root.presentedViewController != nil { return hit }

        var candidate: UIView? = hit
        while let view = candidate {
            if view is UIControl { return hit }
            if view === root.view { break }
            candidate = view.superview
        }
        return nil
    }
}

final class PlayerOverlayHostingController<Content: View>: UIHostingController<Content> {
    override var prefersStatusBarHidden: Bool { true }
}
