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
                    ChannelLogoView(url: channel.logoURL, size: 54)

                    Spacer(minLength: 0)

                    HStack(spacing: Theme.Spacing.xs) {
                        Circle()
                            .fill(Theme.Palette.live)
                            .frame(width: 6, height: 6)
                        Text("CANLI")
                    }
                    .font(Theme.Typography.badge)
                    .foregroundColor(Theme.Palette.textPrimary)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.18), in: Capsule())
                }

                HStack(spacing: Theme.Spacing.sm) {
                    Text(channel.name)
                        .font(Theme.Typography.rowTitle)
                        .foregroundColor(Theme.Palette.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 0)

                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(brandColor, in: Circle())
                }
            }
            .padding(Theme.Spacing.lg)
            .frame(width: 184, height: 138, alignment: .topLeading)
            .background(
                LinearGradient(
                    colors: [brandColor.opacity(0.16), Theme.Palette.surface],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .stroke(brandColor.opacity(0.13), lineWidth: 1)
            }
        }
        .buttonStyle(SearchCardButtonStyle())
        .accessibilityLabel("\(channel.name), canlı yayın")
        .accessibilityHint("Oynatmak için çift dokun")
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
                        .padding(.horizontal, 6)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(Color.black.opacity(0.38), in: Capsule())
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
        .buttonStyle(SearchCardButtonStyle())
        .accessibilityLabel(ratingLabel)
    }

    private var ratingLabel: String {
        guard let rating, rating > 0 else { return title }
        return "\(title), puan \(String(format: "%.1f", rating))"
    }
}

private struct SearchCardButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
