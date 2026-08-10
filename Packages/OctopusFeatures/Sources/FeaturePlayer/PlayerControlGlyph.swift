import UIKit

/// VLC drawable yeniden bağlanırken dahi üstte kalan yerel kontrol glifi.
///
/// Bu görünüm bilinçli olarak `UIHostingController` dışında tutulur. VLC'nin
/// drawable güncellemesi SwiftUI kontrol etiketlerini yeniden çizdiğinde
/// kapat/seçenek simgeleri kaybolmadan video yüzeyinin üstünde kalır.
final class PlayerEdgeGlyphView: UIView {

    enum Kind {
        case close
        case options
    }

    private let kind: Kind
    private let glyphLayer = CAShapeLayer()

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)

        backgroundColor = UIColor.black.withAlphaComponent(0.58)
        layer.cornerRadius = 22
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.white.withAlphaComponent(0.14).cgColor
        layer.addSublayer(glyphLayer)
        clipsToBounds = true
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        glyphLayer.frame = bounds
        glyphLayer.contentsScale = contentScaleFactor

        switch kind {
        case .close:
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 15, y: 15))
            path.addLine(to: CGPoint(x: 29, y: 29))
            path.move(to: CGPoint(x: 29, y: 15))
            path.addLine(to: CGPoint(x: 15, y: 29))
            glyphLayer.path = path.cgPath
            glyphLayer.fillColor = nil
            glyphLayer.strokeColor = UIColor.white.cgColor
            glyphLayer.lineWidth = 2.8
            glyphLayer.lineCap = .round

        case .options:
            let path = UIBezierPath()
            let centers: [CGFloat] = [14, 22, 30]
            for centerX in centers {
                path.append(
                    UIBezierPath(
                        ovalIn: CGRect(x: centerX - 2, y: 20, width: 4, height: 4)
                    )
                )
            }
            glyphLayer.path = path.cgPath
            glyphLayer.fillColor = UIColor.white.cgColor
            glyphLayer.strokeColor = nil
        }
    }
}
