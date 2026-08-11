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
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
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

            HStack(spacing: Theme.Spacing.xs) {
                Button("İptal", action: onCancel)
                    .buttonStyle(.bordered)
                Button("Şimdi oynat", action: onPlay)
                    .buttonStyle(.borderedProminent)
            }
            .tint(Theme.Palette.accent)
            .controlSize(.small)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(maxWidth: 320, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.14), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        // Zaman çizgisi ve süre etiketleri oynatılabilir kalmalı.
        .padding(.trailing, Theme.Spacing.md)
        .padding(.bottom, 74)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }
}
