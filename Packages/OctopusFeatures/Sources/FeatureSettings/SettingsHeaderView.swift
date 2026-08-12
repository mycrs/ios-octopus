import SwiftUI
import OctopusDesignSystem

/// Marka kimliğini kaybetmeden ayarlara sakin bir giriş yüzeyi verir.
struct SettingsHeaderView: View {

    let name: String
    let logoURL: URL?
    @Environment(\.brandColor) private var brandColor

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            logo

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(name)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(Theme.Palette.textPrimary)
                    .lineLimit(1)

                Text("Deneyimini kişiselleştir")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Palette.textSecondary)
            }

            Spacer(minLength: Theme.Spacing.sm)

            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(brandColor)
                .frame(width: 36, height: 36)
                .background(brandColor.opacity(0.12), in: Circle())
        }
        .settingsSurface()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var logo: some View {
        if let logoURL {
            RemoteImageView(url: logoURL, contentMode: .fit, targetWidth: 112) {
                DefaultBrandLogoView()
            }
            .frame(width: 56, height: 56)
        } else {
            DefaultBrandLogoView()
                .frame(width: 56, height: 56)
        }
    }
}
