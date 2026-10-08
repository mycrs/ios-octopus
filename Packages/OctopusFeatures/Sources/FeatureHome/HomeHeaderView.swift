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
            Theme.Palette.surface

            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                brandRow
                greetingBlock
                HomeHeroAccountView(account: account)
                actions
            }
            .padding(Theme.Spacing.xl)
        }
        .frame(maxWidth: .infinity, minHeight: 304, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .stroke(Theme.Palette.separator, lineWidth: 1)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.sm)
    }

    @ViewBuilder
    private var brandRow: some View {
        if dynamicTypeSize >= .xxLarge {
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

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(brandName)
                    .font(Theme.Typography.rowTitle.weight(.semibold))
                    .foregroundColor(Theme.Palette.textPrimary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)

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
        .accessibilityLabel(AppLocalization.localized("Saat", locale: locale))
    }

    private var greetingBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(AppLocalization.localized(greeting, locale: locale))
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundColor(Theme.Palette.textPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)

            Text(AppLocalization.localized("Bugün ne izlemek istersin?", locale: locale))
                .font(Theme.Typography.rowSubtitle)
                .foregroundColor(Theme.Palette.textSecondary)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if dynamicTypeSize >= .xxLarge {
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
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .opacity(0.72)
            }
            .font(Theme.Typography.caption.weight(.semibold))
            .foregroundColor(isPrimary ? Theme.contentColor(on: brandColor) : Theme.Palette.textPrimary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
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

}
