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
    private let overlay: Overlay
    @Environment(\.brandColor) private var brandColor

    init(
        makeSurface: @escaping () -> UIView?,
        @ViewBuilder overlay: () -> Overlay
    ) {
        self.makeSurface = makeSurface
        self.overlay = overlay()
    }

    func makeUIViewController(context: Context) -> PlayerSurfaceViewController {
        PlayerSurfaceViewController(
            surface: makeSurface(),
            overlay: hostedOverlay
        )
    }

    func updateUIViewController(
        _ controller: PlayerSurfaceViewController,
        context: Context
    ) {
        controller.update(overlay: hostedOverlay)
    }

    private var hostedOverlay: AnyView {
        AnyView(
            overlay
                .environment(\.brandColor, brandColor)
                .preferredColorScheme(.dark)
        )
    }
}

final class PlayerSurfaceViewController: UIViewController {

    private let surface: UIView?
    private let overlayHost: UIHostingController<AnyView>

    init(surface: UIView?, overlay: AnyView) {
        self.surface = surface
        self.overlayHost = UIHostingController(rootView: overlay)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        if let surface {
            pin(surface, to: view)
        }

        addChild(overlayHost)
        overlayHost.view.backgroundColor = .clear
        overlayHost.view.isOpaque = false
        pin(overlayHost.view, to: view.safeAreaLayoutGuide)
        overlayHost.didMove(toParent: self)
        view.bringSubviewToFront(overlayHost.view)
    }

    func update(overlay: AnyView) {
        overlayHost.rootView = overlay
        view.bringSubviewToFront(overlayHost.view)
    }

    private func pin(_ child: UIView, to guide: UILayoutGuide) {
        child.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            child.topAnchor.constraint(equalTo: guide.topAnchor),
            child.bottomAnchor.constraint(equalTo: guide.bottomAnchor)
        ])
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
