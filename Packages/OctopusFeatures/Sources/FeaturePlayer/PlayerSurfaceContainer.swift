import SwiftUI
import UIKit
import OctopusDesignSystem

/// Video yüzeyi ile SwiftUI denetimlerini aynı UIKit hiyerarşisinde tutar.
///
/// VLC'nin OpenGL görünümü tam ekranda ayrı SwiftUI kardeşlerinin önüne
/// çıkabiliyor; dokunma çalışsa da denetimler görünmüyordu. Denetim katmanı
/// burada `UIHostingController` ile video yüzeyinden sonra eklenir ve her
/// güncellemede öne alınır. AVPlayer ve VLC aynı kabı kullanır.
struct PlayerSurfaceContainer<Overlay: View>: UIViewControllerRepresentable {

    private let makeSurface: () -> UIView?
    private let surfaceGeneration: Int
    private let overlay: Overlay
    @Environment(\.brandColor) private var brandColor

    init(
        makeSurface: @escaping () -> UIView?,
        surfaceGeneration: Int,
        @ViewBuilder overlay: () -> Overlay
    ) {
        self.makeSurface = makeSurface
        self.surfaceGeneration = surfaceGeneration
        self.overlay = overlay()
    }

    func makeUIViewController(
        context: Context
    ) -> PlayerSurfaceViewController<PlayerHostedOverlay<Overlay>> {
        PlayerSurfaceViewController(
            surface: makeSurface(),
            surfaceGeneration: surfaceGeneration,
            overlay: hostedOverlay
        )
    }

    func updateUIViewController(
        _ controller: PlayerSurfaceViewController<PlayerHostedOverlay<Overlay>>,
        context: Context
    ) {
        controller.update(
            surfaceGeneration: surfaceGeneration,
            makeSurface: makeSurface,
            overlay: hostedOverlay
        )
    }

    private var hostedOverlay: PlayerHostedOverlay<Overlay> {
        PlayerHostedOverlay(content: overlay, brandColor: brandColor)
    }
}

/// `AnyView` kullanılmaz: VOD süresi her güncellendiğinde tip silinmiş ağacı
/// baştan kurmak, hızlandırılmış video üstünde kısa süreli glif kaybı yaratıyordu.
struct PlayerHostedOverlay<Content: View>: View {
    let content: Content
    let brandColor: Color

    var body: some View {
        content
            .environment(\.brandColor, brandColor)
            .preferredColorScheme(.dark)
    }
}

final class PlayerSurfaceViewController<Overlay: View>: UIViewController {

    private var surface: UIView?
    private var surfaceGeneration: Int
    private var overlayConstraints: [NSLayoutConstraint] = []
    let overlayHost: UIHostingController<Overlay>

    init(
        surface: UIView?,
        surfaceGeneration: Int,
        overlay: Overlay
    ) {
        self.surface = surface
        self.surfaceGeneration = surfaceGeneration
        self.overlayHost = UIHostingController(rootView: overlay)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = .black

        if let surface {
            install(surface)
        }

        addChild(overlayHost)
        overlayHost.view.backgroundColor = .clear
        overlayHost.view.isOpaque = false
        overlayHost.view.layer.zPosition = 1_000
        attachOverlay()
        overlayHost.didMove(toParent: self)
        bringOverlayToFront()
    }

    func update(
        surfaceGeneration: Int,
        makeSurface: () -> UIView?,
        overlay: Overlay
    ) {
        replaceSurfaceIfNeeded(
            generation: surfaceGeneration,
            makeSurface: makeSurface
        )
        overlayHost.rootView = overlay
        bringOverlayToFront()
    }

    private func replaceSurfaceIfNeeded(
        generation: Int,
        makeSurface: () -> UIView?
    ) {
        guard generation != surfaceGeneration else { return }
        surfaceGeneration = generation
        detachOverlay()
        surface?.removeFromSuperview()
        surface = makeSurface()
        if let surface {
            install(surface)
        }
        attachOverlay()
    }

    private func install(_ surface: UIView) {
        // VLCKit kendi renderer görünümünü bu yüzeye sonradan ekler. Kırpma,
        // renderer'ın drawable sınırlarının dışına taşmasını engeller.
        surface.clipsToBounds = true
        surface.layer.zPosition = 0
        pin(surface, to: view)
    }

    private func bringOverlayToFront() {
        overlayHost.view.superview?.bringSubviewToFront(overlayHost.view)
    }

    private func attachOverlay() {
        // VLC, drawable içine kendi opak OpenGL görünümünü sonradan ekler.
        // Host'u drawable'ın içinde ve daha yüksek z düzleminde tutmak,
        // renderer'ın SwiftUI gliflerini aralıklı olarak kapatmasını önler.
        guard let parent = surface ?? view else { return }
        overlayHost.loadViewIfNeeded()
        guard let child = overlayHost.view else { return }
        child.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(child)
        overlayConstraints = [
            child.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            child.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            child.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ]
        NSLayoutConstraint.activate(overlayConstraints)
        bringOverlayToFront()
    }

    private func detachOverlay() {
        NSLayoutConstraint.deactivate(overlayConstraints)
        overlayConstraints.removeAll()
        overlayHost.view.removeFromSuperview()
    }

    private func pin(_ child: UIView, to parent: UIView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor)
        ])
    }
}
