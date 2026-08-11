import SwiftUI
import OctopusDesignSystem

struct PlayerLockControl: View {
    let isLocked: Bool
    let action: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        Button(action: action) {
            Image(systemName: isLocked ? "lock.fill" : "lock.open")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle().stroke(.white.opacity(0.14), lineWidth: 0.5)
                }
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            AppLocalization.localized(
                isLocked ? "Oynatıcı kilidini aç" : "Oynatıcıyı kilitle",
                locale: locale
            )
        )
    }
}
