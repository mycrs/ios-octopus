import UIKit
import AVFoundation

/// `AVPlayerLayer` taşıyan UIKit görünümü.
///
/// ## Neden `layerClass` üzerinden?
/// Katmanı elle ekleyip `layoutSubviews`'ta yeniden boyutlandırmak yaygın
/// bir yöntem ama her dönüşte bir kare gecikme yaratır: görünüm yeni
/// boyuta geçer, katman bir sonraki döngüde yetişir — cihaz döndürülünce
/// video bir an yamuk görünür. `layerClass` ile katman **görünümün
/// kendisidir**; boyutu her zaman birebir aynıdır.
final class PlayerLayerView: UIView {

    override class var layerClass: AnyClass { AVPlayerLayer.self }

    /// Katmana tip güvenli erişim. `as!` yasak (bkz. CLAUDE.md), bu yüzden
    /// isteğe bağlı dönüşüm — `layerClass` sayesinde asla `nil` olmaz.
    var playerLayer: AVPlayerLayer? { layer as? AVPlayerLayer }

    var player: AVPlayer? {
        get { playerLayer?.player }
        set { playerLayer?.player = newValue }
    }

    /// Görüntü çerçeveye nasıl sığsın?
    ///
    /// Varsayılan `.resizeAspect`: en-boy oranı korunur, kenarlarda siyah
    /// bant kalabilir. Kullanıcı "ekranı doldur"u seçerse `.resizeAspectFill`.
    var videoGravity: AVLayerVideoGravity {
        get { playerLayer?.videoGravity ?? .resizeAspect }
        set { playerLayer?.videoGravity = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        // Storyboard kullanılmıyor. `fatalError` yerine `nil`: zorlama
        // (force) yasağı derleme zamanı kuralımız, çalışma zamanı çökmesi değil.
        nil
    }
}
