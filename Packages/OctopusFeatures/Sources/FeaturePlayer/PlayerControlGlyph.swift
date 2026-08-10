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

/// Glifin her parçası ayrı bir UIKit view'ıdır; yalnızca kendi ana katmanının
/// `backgroundColor` özelliğini kullanır. VLC kompozitörü içerik ve özel alt
/// katmanları atlasa bile bu parçalar kontrol zeminiyle aynı yoldan çizilir.
final class PlayerEdgeMarkView: UIView {

    init(cornerRadius: CGFloat, rotation: CGFloat = 0) {
        super.init(frame: .zero)
        backgroundColor = .white
        layer.cornerRadius = cornerRadius
        transform = CGAffineTransform(rotationAngle: rotation)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}
