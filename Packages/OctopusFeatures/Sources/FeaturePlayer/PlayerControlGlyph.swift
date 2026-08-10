import UIKit

/// VLC drawable yeniden bağlanırken dahi üstte kalan yerel kontrol zemini.
final class PlayerEdgeControlBackgroundView: UIView {

    init() {
        super.init(frame: .zero)
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
