import SwiftUI
import OctopusDomain
import OctopusDesignSystem

/// Sezon seçici. Tek sezonlu dizilerde hiç gösterilmez.
struct SeasonPickerView: View {

    let seasons: [Season]
    let selectedNumber: Int?
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(seasons) { season in
                    Button {
                        onSelect(season.number)
                    } label: {
                        Text(season.name ?? "\(season.number). Sezon")
                            .font(Theme.Typography.caption)
                            .lineLimit(1)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm)
                            .background(
                                selectedNumber == season.number
                                    ? Theme.Palette.accentMuted
                                    : Theme.Palette.surface
                            )
                            .foregroundColor(
                                selectedNumber == season.number
                                    ? Theme.Palette.accent
                                    : Theme.Palette.textSecondary
                            )
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }
}

/// Bölüm satırı: kapak, başlık, izlendi işareti veya kaldığı yer çubuğu.
struct EpisodeRowView: View {

    let episode: Episode
    let isWatched: Bool
    let progress: Double?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    RemoteImageView(url: episode.stillURL, contentMode: .fill, targetWidth: 96) {
                        ZStack {
                            Theme.Palette.surfaceElevated
                            Image(systemName: "play.rectangle")
                                .foregroundColor(Theme.Palette.textTertiary)
                        }
                    }
                    .frame(width: 96, height: 54)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))

                    if isWatched {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Theme.Palette.success)
                            .background(Circle().fill(.black.opacity(0.4)))
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text("\(episode.number). \(episode.title)")
                        .font(Theme.Typography.rowTitle)
                        .foregroundColor(
                            isWatched ? Theme.Palette.textSecondary : Theme.Palette.textPrimary
                        )
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if let durationSeconds = episode.durationSeconds, durationSeconds > 0 {
                        Text("\(durationSeconds / 60) dk")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Palette.textTertiary)
                    }

                    if let progress {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(Theme.Palette.accent)
                            .frame(height: 2)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.sm)
            .background(Theme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
