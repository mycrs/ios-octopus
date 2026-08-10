import SwiftUI
import UIKit

enum PlayerEdgeGlyph {
    case close
    case options
}

struct PlayerEdgeControl: View {
    let glyph: PlayerEdgeGlyph
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(uiImage: PlayerEdgeControlImage.image(for: glyph))
                .resizable()
                .interpolation(.high)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(PlayerEdgeButtonStyle())
        .accessibilityLabel(label)
    }
}

private struct PlayerEdgeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.58 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
