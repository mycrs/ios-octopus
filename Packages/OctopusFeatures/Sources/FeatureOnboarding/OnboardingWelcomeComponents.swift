import SwiftUI
import OctopusDesignSystem

struct OnboardingBackgroundGlow: View {
    let opacity: Double
    let center: UnitPoint
    let endRadius: CGFloat
    @Environment(\.brandColor) private var brandColor

    var body: some View {
        RadialGradient(
            colors: [brandColor.opacity(opacity), .clear],
            center: center,
            startRadius: 0,
            endRadius: endRadius
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct OnboardingWelcomeBrand: View {
    let brandName: String
    let logoURL: URL?
    @Environment(\.brandColor) private var brandColor

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            brandMark

            VStack(spacing: Theme.Spacing.sm) {
                Text(brandName)
                    .font(Theme.Typography.screenTitle)
                    .foregroundColor(Theme.Palette.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Televizyon deneyimin, tek bir yerde.")
                    .font(Theme.Typography.rowSubtitle)
                    .foregroundColor(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private var brandMark: some View {
        if let logoURL {
            RemoteImageView(url: logoURL, contentMode: .fit, targetWidth: 184) {
                defaultMark
            }
            .frame(width: 92, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: brandColor.opacity(0.18), radius: 24, y: 10)
        } else {
            defaultMark
        }
    }

    private var defaultMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                }

            Circle()
                .fill(brandColor.opacity(0.13))
                .frame(width: 64, height: 64)

            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 38, weight: .medium))
                .foregroundColor(brandColor)
        }
        .frame(width: 92, height: 92)
        .shadow(color: brandColor.opacity(0.18), radius: 24, y: 10)
    }
}

struct OnboardingCapabilities: View {
    @Environment(\.brandColor) private var brandColor
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            capability("tv", "Canlı TV", "Kategoriler, favoriler ve yayın akışı")
            capability("film", "Film ve dizi", "Kaldığın yerden devam et")
            capability("lock.shield", "Ebeveyn kilidi", "Yetişkin içeriği gizle")
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Palette.surface.opacity(0.54))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
    }

    private func capability(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(brandColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(AppLocalization.localized(title, locale: locale))
                    .font(Theme.Typography.rowTitle)
                    .foregroundColor(Theme.Palette.textPrimary)
                Text(AppLocalization.localized(detail, locale: locale))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Palette.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

struct OnboardingResellerCodeButton: View {
    let savedCode: String?
    let action: () -> Void
    @Environment(\.brandColor) private var brandColor
    @Environment(\.locale) private var locale

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "person.badge.key")
                    .foregroundColor(brandColor)
                Text(
                    AppLocalization.localized(
                        savedCode == nil ? "Hizmet sağlayıcımı bağla" : "Marka bağlantısı aktif",
                        locale: locale
                    )
                )
                Spacer(minLength: Theme.Spacing.sm)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Theme.Palette.textTertiary)
            }
            .font(Theme.Typography.caption.weight(.semibold))
            .foregroundColor(Theme.Palette.textSecondary)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(Theme.Palette.surface.opacity(0.64))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
