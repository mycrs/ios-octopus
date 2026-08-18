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
        OnboardingBrandLogo(logoURL: logoURL, size: 92)
        .shadow(color: brandColor.opacity(0.18), radius: 24, y: 10)
    }
}

/// Kurulum akışındaki bütün marka yüzeylerinin aynı logo/fallback kuralını kullanmasını sağlar.
struct OnboardingBrandLogo: View {
    let logoURL: URL?
    let size: CGFloat

    @ViewBuilder
    var body: some View {
        if let logoURL {
            RemoteImageView(url: logoURL, contentMode: .fit, targetWidth: size * 2) {
                fallback
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
        } else {
            fallback
        }
    }

    private var fallback: some View {
        DefaultBrandLogoView()
            .frame(width: size, height: size)
    }
}

struct OnboardingCapabilities: View {
    @Environment(\.brandColor) private var brandColor
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            capability("tv", "Canlı TV", "Kategoriler, favoriler ve yayın akışı")
            capability("film", "Film ve dizi", "Kaldığın yerden devam et")
            capability(
                "bolt.horizontal.circle",
                "Kesintisiz oynatma",
                "Yayın koparsa kendiliğinden geri döner"
            )
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

/// Uygulamanın içerik sağlamadığını söyleyen not.
///
/// ⚠️ Yalnızca hukuki bir dipnot değil, **App Store incelemesi** için de
/// gerekli: Apple, IPTV istemcilerini "telifli içeriğe erişimi
/// kolaylaştırıyor" gerekçesiyle (Guideline 5.2.3) sıkça reddediyor.
/// Uygulamanın içerik barındırmadığı ve kaynağın kullanıcıya ait olduğu
/// ilk ekranda açıkça yazılı olmalı — inceleyen kişi bunu görmeli.
struct OnboardingContentDisclaimer: View {
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundColor(Theme.Palette.textTertiary)

            // ⚠️ Marka adı **yazılmıyor**: uygulama bayiye göre "Qruze
            // Player" gibi başka bir adla açılabiliyor. Sabit "Octopus"
            // yazsaydı beyaz etiketli kurulumlarda yanlış ada işaret ederdi.
            Text(
                AppLocalization.localized(
                    "Bu uygulama yalnızca bir oynatıcıdır: içerik sağlamaz ve barındırmaz. Yayınlar eklediğin kendi aboneliğinden gelir.",
                    locale: locale
                )
            )
            .font(Theme.Typography.caption)
            .foregroundColor(Theme.Palette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
