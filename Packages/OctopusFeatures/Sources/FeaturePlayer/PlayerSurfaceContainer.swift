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
    private let showsEdgeGlyphs: Bool
    private let overlay: Overlay
    @Environment(\.brandColor) private var brandColor

    init(
        makeSurface: @escaping () -> UIView?,
        showsEdgeGlyphs: Bool,
        @ViewBuilder overlay: () -> Overlay
    ) {
        self.makeSurface = makeSurface
        self.showsEdgeGlyphs = showsEdgeGlyphs
        self.overlay = overlay()
    }

    func makeUIViewController(context: Context) -> PlayerSurfaceViewController {
        PlayerSurfaceViewController(
            surface: makeSurface(),
            overlay: hostedOverlay,
            showsEdgeGlyphs: showsEdgeGlyphs
        )
    }

    func updateUIViewController(
        _ controller: PlayerSurfaceViewController,
        context: Context
    ) {
        controller.update(
            overlay: hostedOverlay,
            showsEdgeGlyphs: showsEdgeGlyphs
        )
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
    let overlayHost: UIHostingController<AnyView>
    let closeBackground = PlayerEdgeControlBackgroundView()
    let optionsBackground = PlayerEdgeControlBackgroundView()
    let closeForwardMark = PlayerEdgeMarkView(
        cornerRadius: 1.5,
        rotation: CGFloat.pi / 4
    )
    let closeBackwardMark = PlayerEdgeMarkView(
        cornerRadius: 1.5,
        rotation: -CGFloat.pi / 4
    )
    let optionsLeftMark = PlayerEdgeMarkView(cornerRadius: 2)
    let optionsCenterMark = PlayerEdgeMarkView(cornerRadius: 2)
    let optionsRightMark = PlayerEdgeMarkView(cornerRadius: 2)
    var showsEdgeGlyphs: Bool

    var edgeViews: [UIView] {
        [
            closeBackground,
            optionsBackground,
            closeForwardMark,
            closeBackwardMark,
            optionsLeftMark,
            optionsCenterMark,
            optionsRightMark
        ]
    }

    init(surface: UIView?, overlay: AnyView, showsEdgeGlyphs: Bool) {
        self.surface = surface
        self.overlayHost = UIHostingController(rootView: overlay)
        self.showsEdgeGlyphs = showsEdgeGlyphs
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = .black

        if let surface {
            pin(surface, to: view)
        }

        addChild(overlayHost)
        overlayHost.view.backgroundColor = .clear
        overlayHost.view.isOpaque = false
        pin(overlayHost.view, to: view.safeAreaLayoutGuide)
        overlayHost.didMove(toParent: self)
        installEdgeGlyphs()
        refreshOverlayOrder()
    }

    func update(overlay: AnyView, showsEdgeGlyphs: Bool) {
        overlayHost.rootView = overlay
        self.showsEdgeGlyphs = showsEdgeGlyphs
        edgeViews.forEach {
            $0.isHidden = !showsEdgeGlyphs
        }
        refreshOverlayOrder()
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
