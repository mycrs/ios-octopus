import SwiftUI
import UIKit

/// Motorun ürettiği UIKit video görünümünü SwiftUI'a taşır.
///
/// ⚠️ Görünüm **motor tarafından** üretilir; burada AVFoundation ya da
/// VLCKit adı geçmez. Oynatıcı ekranı hangi motorun çalıştığını bilmez —
/// mimarinin bu ekranda görünen karşılığı tam olarak budur.
///
/// ⚠️ Motor değiştiğinde (native → VLC) yeni bir yüzey gerekir. SwiftUI
/// aynı `UIViewRepresentable`'ı yeniden kullanacağından, çağıran taraf
/// `.id(engineIdentifier)` vererek görünümü baştan kurdurur.
struct VideoSurfaceView: UIViewRepresentable {

    /// Motordan yüzey isteyen kapanış. `nil` dönerse siyah zemin çizilir.
    let makeSurface: () -> UIView?

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black

        guard let surface = makeSurface() else { return container }

        surface.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(surface)

        // Kenarlara sabitlenir: video katmanı görünümle birebir aynı
        // boyutta kalmalı, aksi hâlde dönüşte bir kare yamuk görünür.
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            surface.topAnchor.constraint(equalTo: container.topAnchor),
            surface.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Yüzeyin içeriğini motor günceller; SwiftUI tarafında yapılacak
        // bir şey yok. Boş bırakmak kasıtlı.
    }
}
