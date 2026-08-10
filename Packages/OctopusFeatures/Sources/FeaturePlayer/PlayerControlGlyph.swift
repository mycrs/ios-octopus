import UIKit

/// VLC drawable yeniden bağlanırken dahi üstte kalan yerel kontrol glifi.
///
/// Bu görünüm bilinçli olarak `UIHostingController` dışında tutulur. VLC'nin
/// drawable güncellemesi SwiftUI kontrol etiketlerini yeniden çizdiğinde
/// kapat/seçenek simgeleri kaybolmadan video yüzeyinin üstünde kalır.
final class PlayerEdgeGlyphView: UIImageView {

    init(systemName: String) {
        let configuration = UIImage.SymbolConfiguration(
            pointSize: systemName == "xmark" ? 20 : 18,
            weight: .semibold
        )
        super.init(
            image: UIImage(
                systemName: systemName,
                withConfiguration: configuration
            )?.withRenderingMode(.alwaysTemplate)
        )

        tintColor = .white
        contentMode = .center
        backgroundColor = UIColor.black.withAlphaComponent(0.58)
        layer.cornerRadius = 22
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.white.withAlphaComponent(0.14).cgColor
        clipsToBounds = true
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}
