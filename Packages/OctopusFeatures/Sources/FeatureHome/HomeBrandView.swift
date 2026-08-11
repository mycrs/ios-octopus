import SwiftUI
import OctopusDesignSystem

/// Ana sayfa navigasyonundaki marka kilidi.
/// Bayi logosu yoksa uygulamanın kendi işareti görünür; alan hiçbir zaman boş kalmaz.
struct HomeNavigationBrand: View {
    let name: String
    let logoURL: URL?

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            HomeBrandLogo(logoURL: logoURL, size: 34)

            Text(name)
                .font(Theme.Typography.rowTitle.weight(.semibold))
                .foregroundColor(Theme.Palette.textPrimary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name)
    }
}

struct HomeBrandLogo: View {
    let logoURL: URL?
    let size: CGFloat

    var body: some View {
        Group {
            if let logoURL {
                RemoteImageView(url: logoURL, contentMode: .fit, targetWidth: size * 2) {
                    fallback
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
    }

    private var fallback: some View {
        DefaultBrandLogoView()
    }
}
