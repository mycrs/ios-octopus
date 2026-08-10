import SwiftUI
import UIKit

enum PlayerEdgeGlyph {
    case close
    case options
}

struct PlayerEdgeControl: UIViewRepresentable {
    let glyph: PlayerEdgeGlyph
    let label: String
    let action: () -> Void

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func activate() {
            action()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> PlayerEdgeControlView {
        let control = PlayerEdgeControlView()
        control.addTarget(
            context.coordinator,
            action: #selector(Coordinator.activate),
            for: .touchUpInside
        )
        configure(control)
        return control
    }

    func updateUIView(_ control: PlayerEdgeControlView, context: Context) {
        context.coordinator.action = action
        configure(control)
    }

    private func configure(_ control: PlayerEdgeControlView) {
        control.glyph = glyph
        control.isAccessibilityElement = true
        control.accessibilityTraits = .button
        control.accessibilityLabel = label
    }
}

final class PlayerEdgeControlView: UIControl {
    let imageView = UIImageView()

    var glyph: PlayerEdgeGlyph = .close {
        didSet { updateImage() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        imageView.frame = bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = false
        addSubview(imageView)
        updateImage()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.55 : 1 }
    }

    private func updateImage() {
        imageView.image = PlayerEdgeControlImage.image(for: glyph)
    }
}

enum PlayerEdgeControlImage {
    static let size = CGSize(width: 44, height: 44)

    private static let closeImage = decode(PlayerEdgeControlAssets.closePNG)
    private static let optionsImage = decode(PlayerEdgeControlAssets.optionsPNG)

    static func image(for glyph: PlayerEdgeGlyph) -> UIImage {
        switch glyph {
        case .close: return closeImage
        case .options: return optionsImage
        }
    }

    private static func decode(_ base64: String) -> UIImage {
        guard
            let data = Data(base64Encoded: base64),
            let image = UIImage(data: data, scale: 3)
        else {
            assertionFailure("Oynatıcı kenar görseli çözülemedi")
            return UIImage()
        }
        return image.withRenderingMode(.alwaysOriginal)
    }
}
