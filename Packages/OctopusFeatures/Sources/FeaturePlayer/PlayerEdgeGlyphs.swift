import SwiftUI
import OctopusDesignSystem

enum PlayerEdgeGlyph {
    case close
    case options
}

struct PlayerEdgeControl: View {
    let glyph: PlayerEdgeGlyph
    let label: String
    let action: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        Button(action: action) {
            Image(systemName: glyph.systemName)
                .font(.system(size: glyph.iconSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle().stroke(.white.opacity(0.14), lineWidth: 0.5)
                }
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(PlayerEdgeButtonStyle())
        .accessibilityLabel(AppLocalization.localized(label, locale: locale))
    }
}

private extension PlayerEdgeGlyph {
    var iconSize: CGFloat {
        switch self {
        case .close: return 15
        case .options: return 17
        }
    }

    var systemName: String {
        switch self {
        case .close: return "xmark"
        case .options: return "ellipsis"
        }
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
