import SwiftUI
import OctopusDomain
import OctopusDesignSystem

struct NextEpisodeOverlay: View {
    let episode: Episode
    let countdown: Int
    let onPlay: () -> Void
    let onCancel: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Sıradaki bölüm")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.accent)

            Text(episode.title)
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(.white)
                .lineLimit(2)

            Text(
                AppLocalization.localized(
                    "%@ · %ld sn sonra oynatılacak",
                    locale: locale,
                    episode.shortLabel,
                    countdown
                )
            )
                .font(Theme.Typography.caption)
                .foregroundStyle(.white.opacity(0.68))

            HStack(spacing: Theme.Spacing.sm) {
                Button("İptal", action: onCancel)
                    .buttonStyle(.bordered)
                Button("Şimdi oynat", action: onPlay)
                    .buttonStyle(.borderedProminent)
            }
            .tint(Theme.Palette.accent)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: 330, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.14), lineWidth: 0.5)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }
}
