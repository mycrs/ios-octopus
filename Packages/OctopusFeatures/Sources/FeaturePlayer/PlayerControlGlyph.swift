import SwiftUI
import UIKit

/// VLC drawable yeniden bağlanırken kaybolmayan, UIKit tabanlı kontrol glifi.
///
/// SwiftUI `Text`/SF Symbol ön planı VLC'nin video katmanıyla aynı karede
/// bazen atlanıyor; gerçek `UILabel` ise hosting hiyerarşisinde kalıyor.
struct PlayerControlGlyph: UIViewRepresentable {

    let text: String

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.textAlignment = .center
        label.backgroundColor = UIColor.black.withAlphaComponent(0.58)
        label.layer.cornerRadius = 22
        label.layer.borderWidth = 0.5
        label.layer.borderColor = UIColor.white.withAlphaComponent(0.14).cgColor
        label.clipsToBounds = true
        label.isUserInteractionEnabled = false
        configure(label)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        configure(label)
    }

    private func configure(_ label: UILabel) {
        let isClose = text == "×"
        label.font = .systemFont(
            ofSize: isClose ? 28 : 14,
            weight: isClose ? .medium : .bold
        )
        label.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .foregroundColor: UIColor.white,
                .kern: isClose ? 0 : 1.5
            ]
        )
    }
}
