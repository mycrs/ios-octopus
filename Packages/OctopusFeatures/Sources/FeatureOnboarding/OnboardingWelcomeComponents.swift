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
    }
}

/// Kurulum akışındaki bütün marka yüzeylerinin aynı logo/fallback kuralını kullanmasını sağlar.
struct OnboardingBrandLogo: View {
    let logoURL: URL?
    let size: CGFloat

    var body: some View {
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
                "slider.horizontal.3",
                "Oynatıcı ayarları",
                "Ses, altyazı ve ekran seçenekleri"
            )
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Palette.surface)
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

/// Kullanıcının kendi kaynağı ile isteğe bağlı örnek içeriği açıkça ayırır.
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
                    "Yasal yayın kaynağını ekleyebilir veya açık lisanslı örnek filmlerle uygulamayı keşfedebilirsin. Kendi kaynaklarının kullanım hakkından sen sorumlusun.",
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
