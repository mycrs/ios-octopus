import SwiftUI
import OctopusDesignSystem

/// Ana sayfanın sakin, marka uyumlu karşılama alanı.
/// Teknik kaynak bilgileri yerine kimlik, hesap özeti ve iki ana izleme eylemini sunar.
struct HomeHeaderView: View {
    let account: HomeAccount?
    let greeting: String
    let brandName: String
    let brandLogoURL: URL?
    let onWatchLive: () -> Void
    let onExplore: () -> Void

    @Environment(\.brandColor) private var brandColor
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            premiumBackground
            ambientLight

            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                brandRow
                greetingBlock
                HomeHeroAccountView(account: account)
                actions
            }
            .padding(Theme.Spacing.xl)
        }
        .frame(maxWidth: .infinity, minHeight: 304, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay { premiumBorder }
        .shadow(color: Color.black.opacity(0.30), radius: 24, y: 16)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.sm)
    }

    @ViewBuilder
    private var brandRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                brandIdentity
                clock
            }
        } else {
            HStack(spacing: Theme.Spacing.md) {
                brandIdentity
                Spacer(minLength: Theme.Spacing.sm)
                clock
            }
        }
    }

    private var brandIdentity: some View {
        HStack(spacing: Theme.Spacing.md) {
            HomeBrandLogo(logoURL: brandLogoURL, size: 48)
                .padding(Theme.Spacing.xs)
                .background(Color.white.opacity(0.055), in: RoundedRectangle(
                    cornerRadius: Theme.Radius.lg,
                    style: .continuous
                ))

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(brandName)
                    .font(Theme.Typography.rowTitle.weight(.semibold))
                    .foregroundColor(Theme.Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(AppLocalization.localized("SANA ÖZEL", locale: locale))
                    .font(Theme.Typography.badge)
                    .tracking(0.8)
                    .foregroundColor(brandColor)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(brandColor.opacity(0.12), in: Capsule())
            }
        }
    }

    private var clock: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(context.date, format: .dateTime.hour().minute())
                .monospacedDigit()
                .lineLimit(1)
                .font(Theme.Typography.caption.weight(.semibold))
                .foregroundColor(Theme.Palette.textSecondary)
                .padding(.horizontal, Theme.Spacing.md)
                .frame(minHeight: 32)
                .background(Color.white.opacity(0.055), in: Capsule())
                .overlay {
                    Capsule().stroke(Color.white.opacity(0.07), lineWidth: 1)
                }
        }
        .accessibilityLabel("Saat")
    }

    private var greetingBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(AppLocalization.localized(greeting, locale: locale))
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundColor(Theme.Palette.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.76)

            Text(AppLocalization.localized("Bugün ne izlemek istersin?", locale: locale))
                .font(Theme.Typography.rowSubtitle)
                .foregroundColor(Theme.Palette.textSecondary)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: Theme.Spacing.sm) { actionButtons }
        } else {
            HStack(spacing: Theme.Spacing.sm) { actionButtons }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        heroButton(
            title: "Canlı TV",
            icon: "play.fill",
            isPrimary: true,
            action: onWatchLive
        )
        heroButton(
            title: "Filmleri keşfet",
            icon: "film",
            isPrimary: false,
            action: onExplore
        )
    }

    private func heroButton(
        title: String,
        icon: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(
                        Color.white.opacity(isPrimary ? 0.18 : 0.06),
                        in: Circle()
                    )

                Text(AppLocalization.localized(title, locale: locale))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .opacity(0.72)
            }
            .font(Theme.Typography.caption.weight(.semibold))
            .foregroundColor(isPrimary ? .white : Theme.Palette.textPrimary)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                isPrimary ? brandColor : Color.white.opacity(0.055),
                in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .stroke(
                        Color.white.opacity(isPrimary ? 0.10 : 0.08),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private var premiumBackground: some View {
        LinearGradient(
            colors: [
                Theme.Palette.surfaceElevated,
                Theme.Palette.surface.opacity(0.98),
                Theme.Palette.background.opacity(0.96)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var ambientLight: some View {
        ZStack {
            RadialGradient(
                colors: [brandColor.opacity(0.24), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 260
            )

            RadialGradient(
                colors: [Color.white.opacity(0.055), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 210
            )
        }
        .allowsHitTesting(false)
    }

    private var premiumBorder: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        brandColor.opacity(0.34),
                        Color.white.opacity(0.09),
                        Color.white.opacity(0.035)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }
}
