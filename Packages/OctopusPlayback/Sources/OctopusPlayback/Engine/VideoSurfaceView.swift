import SwiftUI
import UIKit

/// Motorun ürettiği UIKit video görünümünü SwiftUI'a taşır.
///
/// ⚠️ Görünüm **motor tarafından** üretilir; burada AVFoundation ya da
/// VLCKit adı geçmez. Çağıran taraf hangi motorun çalıştığını bilmez —
/// mimarinin bu dosyada görünen karşılığı tam olarak budur.
///
/// ⚠️ Motor değiştiğinde (native → VLC) yeni bir yüzey gerekir. SwiftUI
/// aynı `UIViewRepresentable`'ı yeniden kullanacağından, çağıran taraf
/// `.id(engineIdentifier)` vererek görünümü baştan kurdurur.
///
/// ## Neden `FeaturePlayer`'da değil?
/// Canlı TV ekranındaki gömülü mini oynatıcı da bu yüzeye ihtiyaç duyuyor
/// ve feature'lar birbirini import edemez (bkz. CLAUDE.md demir kural 3).
/// Yüzey oynatma modülüne taşındı: iki ekran da `OctopusPlayback` üzerinden
/// görüyor, aralarında bağ kurulmuyor.
public struct VideoSurfaceView: UIViewRepresentable {

    /// Motordan yüzey isteyen kapanış. `nil` dönerse siyah zemin çizilir.
    private let makeSurface: () -> UIView?

    public init(makeSurface: @escaping () -> UIView?) {
        self.makeSurface = makeSurface
    }

    public func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black

        // Video yüzeyi dokunuş almaz: denetim katmanı üstte ve tüm
        // dokunuşlar ona ait. Kapalı bir üst görünüm `hitTest`'i tüm alt
        // ağaç için `nil` yaptığından motorun eklediği alt görünümler
        // (ör. VLC'nin GL görünümü) de kapsanır.
        container.isUserInteractionEnabled = false

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

    public func updateUIView(_ uiView: UIView, context: Context) {
        // Yüzeyin içeriğini motor günceller; SwiftUI tarafında yapılacak
        // bir şey yok. Boş bırakmak kasıtlı.
    }
}
