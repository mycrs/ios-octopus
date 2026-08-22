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

    final class Coordinator {
        let store: PlayerHostedOverlayStore<Overlay>

        init(content: Overlay, brandColor: Color) {
            store = PlayerHostedOverlayStore(
                content: content,
                brandColor: brandColor
            )
        }
    }

    init(
        makeSurface: @escaping () -> UIView?,
        surfaceGeneration: Int,
        @ViewBuilder overlay: () -> Overlay
    ) {
        self.makeSurface = makeSurface
        self.surfaceGeneration = surfaceGeneration
        self.overlay = overlay()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(content: overlay, brandColor: brandColor)
    }

    func makeUIViewController(
        context: Context
    ) -> PlayerSurfaceViewController<PlayerHostedOverlay<Overlay>> {
        PlayerSurfaceViewController(
            surface: makeSurface(),
            surfaceGeneration: surfaceGeneration,
            overlay: PlayerHostedOverlay(store: context.coordinator.store)
        )
    }

    func updateUIViewController(
        _ controller: PlayerSurfaceViewController<PlayerHostedOverlay<Overlay>>,
        context: Context
    ) {
        context.coordinator.store.update(
            content: overlay,
            brandColor: brandColor
        )
        controller.update(
            surfaceGeneration: surfaceGeneration,
            makeSurface: makeSurface
        )
    }

    /// Ekran kapanırken paylaşılan yüzeyi **serbest bırakır**.
    ///
    /// ⚠️ Atlanamaz: video yüzeyi motora ait ve mini oynatıcıyla
    /// paylaşılıyor. Denetim katmanı ise yüzeyin **içinde** duruyor
    /// (VLC'nin GL görünümü kardeşlerini örttüğü için kasıtlı). Yüzey
    /// serbest bırakılmazsa mini oynatıcı onu geri alırken denetim
    /// katmanını da yanında götürüyor; barındıran controller başka bir
    /// hiyerarşide kalıyor ve UIKit `UIViewControllerHierarchyInconsistency`
    /// ile uygulamayı **çökertiyor** (gerçek cihazda tam ekranı kapatınca
    /// yaşanan tam olarak buydu).
    static func dismantleUIViewController(
        _ controller: PlayerSurfaceViewController<PlayerHostedOverlay<Overlay>>,
        coordinator: Coordinator
    ) {
        controller.releaseSurface()
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

    /// ⚠️ `dismantleUIViewController` **çok geç** kalıyor: mini oynatıcı
    /// yüzeyi ondan önce geri alabiliyor ve çökme oluşuyor. Ekran gözden
    /// kaybolur kaybolmaz yüzeyi bırakmak devrin sırasını garantiliyor.
    ///
    /// Üstte sayfa (iz seçici, kanal paneli) açıldığında bu çağrılmaz —
    /// o sunumlar `viewWillDisappear` tetiklemez, dolayısıyla denetimler
    /// kaybolmaz.
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        releaseSurface()
    }

    func update(
        surfaceGeneration: Int,
        makeSurface: () -> UIView?
    ) {
        replaceSurfaceIfNeeded(
            generation: surfaceGeneration,
            makeSurface: makeSurface
        )
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

    /// Paylaşılan yüzeyi bu ekrandan koparır.
    ///
    /// ⚠️ Denetim katmanı **yok edilmiyor**, kendi görünümümüze geri
    /// taşınıyor. Barındıran controller'ın görünümü kendi ebeveyninin
    /// hiyerarşisinde kaldığı sürece UIKit mutlu; yüzey ise yalnız
    /// başına mini oynatıcıya devredilebiliyor.
    ///
    /// Katman yüzeyin içinde bırakılırsa yüzeyle birlikte taşınıyor,
    /// barındıran controller başka bir hiyerarşide kalıyor ve UIKit
    /// `UIViewControllerHierarchyInconsistency` ile çökertiyor.
    func releaseSurface() {
        // ⚠️ `removeFromSuperview()` **çağrılmıyor** — kasıtlı.
        //
        // Yüzey bir an bile ekransız (superview'suz) kalırsa VLC'nin video
        // çıkışı yıkılıyor ve geri alındığında siyah kalıyor: tam ekrandan
        // mini oynatıcıya dönerken yaşanan buydu. Mini oynatıcı yüzeyi
        // kendi taşıyıcısına eklerken `addSubview` onu eski üst
        // görünümden zaten çıkarıyor; bu **tek adımlık** taşıma çıkışı
        // bozmuyor.
        //
        // Burada yalnızca referans bırakılıyor ki bu controller artık
        // yüzeyi kendi malı sanmasın.
        surface = nil
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
        // ⚠️ Katman **her zaman bu controller'ın kendi görünümüne** eklenir,
        // video yüzeyinin içine değil.
        //
        // Eskiden yüzeyin içine ekleniyordu: VLC drawable'ın içine kendi
        // opak OpenGL görünümünü sonradan ekliyor ve katmanı orada tutmak
        // renderer'ın denetimleri örtmesini önlüyordu. Ne var ki yüzey
        // artık mini oynatıcıyla **paylaşılıyor** ve ekranlar arasında
        // taşınıyor; katman içinde kalınca yüzeyle birlikte gidiyor,
        // barındıran controller yabancı bir hiyerarşide kalıyor ve UIKit
        // `UIViewControllerHierarchyInconsistency` ile uygulamayı
        // çökertiyordu (tam ekranı kapatınca yaşanan buydu).
        //
        // Kardeş olarak eklenip `zPosition` + `bringSubviewToFront` ile
        // öne alınıyor: GL görünümü yüzeyin **alt ağacında** kaldığı için
        // kardeş sıralaması onu da kapsıyor.
        guard let parent = view else { return }
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
