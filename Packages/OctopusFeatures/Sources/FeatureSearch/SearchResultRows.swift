import SwiftUI
import Foundation
import OctopusDomain
import OctopusDesignSystem

struct SearchChannelCard: View {

    let channel: Channel
    let onTap: () -> Void
    @Environment(\.brandColor) private var brandColor

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                HStack(alignment: .top) {
                    ChannelLogoView(url: channel.logoURL, size: 58)

                    Spacer(minLength: 0)

                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 30, height: 30)
                        .background(brandColor, in: Circle())
                }

                Text(channel.name)
                    .font(Theme.Typography.rowTitle)
                    .foregroundColor(Theme.Palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(Theme.Spacing.lg)
            .frame(width: 184, height: 132, alignment: .topLeading)
            .background(
                LinearGradient(
                    colors: [brandColor.opacity(0.12), Theme.Palette.surface],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct SearchPoster: View {

    let title: String
    let posterURL: URL?
    let rating: Double?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                PosterView(url: posterURL, width: 132)

                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.92)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(title)
                        .font(Theme.Typography.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if let rating, rating > 0 {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "star.fill")
                                .foregroundColor(Theme.Palette.warning)
                            Text(String(format: "%.1f", rating))
                                .foregroundColor(.white.opacity(0.86))
                        }
                        .font(Theme.Typography.badge)
                    }
                }
                .padding(Theme.Spacing.sm)
            }
            .frame(width: 132)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.28), radius: 12, y: 7)
        }
        .buttonStyle(.plain)
    }
}
