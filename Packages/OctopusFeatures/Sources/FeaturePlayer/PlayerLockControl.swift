import SwiftUI
import OctopusDesignSystem

struct PlayerLockControl: View {
    let isLocked: Bool
    let action: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        Button(action: action) {
            Image(systemName: isLocked ? "lock.fill" : "lock.open")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.58), in: Circle())
                .overlay {
                    Circle().stroke(.white.opacity(0.14), lineWidth: 0.5)
                }
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
