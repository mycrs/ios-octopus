import SwiftUI
import OctopusDomain
import OctopusDesignSystem

struct PlaylistSubscriptionGateView: View {
    let state: PlaylistSubscriptionMonitor.State
    let onRetry: () -> Void
    let onManageSources: () -> Void
    @Environment(\.brandColor) private var brandColor

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundColor(brandColor)
                Text(state.block?.status == .expired ? "Abonelik süresi doldu" : "Abonelik kullanılamıyor")
                    .font(Theme.Typography.screenTitle)
                    .multilineTextAlignment(.center)
                if let name = state.playlistName {
                    Text(verbatim: name).font(Theme.Typography.rowSubtitle)
                }
                Text("Bu kaynağın erişimini hizmet sağlayıcınla kontrol et. Yenilediysen tekrar kontrol edebilir veya başka bir kaynak kullanabilirsin.")
                    .foregroundColor(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                if let error = state.error {
                    InlineMessageView(text: error.userMessage, kind: .error)
                }
                Button(action: onRetry) {
                    HStack {
                        if state.isChecking { ProgressView().tint(.white) }
                        Text("Aboneliği tekrar kontrol et")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sm)
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.isChecking)
                .accessibilityIdentifier("subscription.retry")
                Button("Başka kaynak kullan", action: onManageSources)
                    .accessibilityIdentifier("subscription.sources")
            }
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("subscription.gate")
    }
}
