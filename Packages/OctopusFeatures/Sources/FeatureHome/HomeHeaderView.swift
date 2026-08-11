import SwiftUI
import OctopusDesignSystem

/// Ana sayfanın sinematik karşılama alanı.
/// Teknik kaynak bilgileri yerine kullanıcının yapmak istediği iki ana işi öne çıkarır.
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
            background
            decoration

            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                brandRow
                greetingBlock
                actions
                HomeHeroAccountView(account: account)
            }
            .padding(Theme.Spacing.xl)
        }
        .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: brandColor.opacity(0.14), radius: 28, y: 14)
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
            HStack {
                brandIdentity
                Spacer(minLength: Theme.Spacing.sm)
                clock
            }
        }
    }

    private var brandIdentity: some View {
        HStack(spacing: Theme.Spacing.md) {
            HomeBrandLogo(logoURL: brandLogoURL, size: 54)
                .shadow(color: brandColor.opacity(0.25), radius: 12, y: 6)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(brandName)
                    .font(Theme.Typography.rowTitle.weight(.bold))
                    .foregroundColor(Theme.Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Label("SANA ÖZEL", systemImage: "sparkles")
                    .font(Theme.Typography.badge)
                    .tracking(0.8)
                    .foregroundColor(brandColor)
            }
        }
    }

    private var clock: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "clock")
                Text(context.date, format: .dateTime.hour().minute())
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .font(Theme.Typography.caption.weight(.semibold))
            .foregroundColor(Theme.Palette.textPrimary)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(minHeight: 32)
            .background(Color.black.opacity(0.16), in: Capsule())
        }
        .accessibilityLabel("Saat")
    }

    private var greetingBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(AppLocalization.localized(greeting, locale: locale))
                .font(Theme.Typography.screenTitle)
                .foregroundColor(Theme.Palette.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.78)

            Text("Bugün ne izlemek istersin?")
                .font(Theme.Typography.rowSubtitle)
                .foregroundColor(Theme.Palette.textSecondary)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: Theme.Spacing.sm) {
                actionButtons
            }
        } else {
            HStack(spacing: Theme.Spacing.sm) {
                actionButtons
            }
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
            icon: "film.fill",
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
            Label {
                Text(AppLocalization.localized(title, locale: locale))
            } icon: {
                Image(systemName: icon)
            }
                .font(Theme.Typography.caption.weight(.semibold))
                .foregroundColor(isPrimary ? .white : Theme.Palette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(isPrimary ? brandColor : Color.white.opacity(0.09))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .stroke(Color.white.opacity(isPrimary ? 0.08 : 0.12), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private var background: some View {
        LinearGradient(
            colors: [
                brandColor.opacity(0.34),
                Theme.Palette.surfaceElevated,
                Theme.Palette.surface
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var decoration: some View {
        ZStack {
            Circle()
                .fill(brandColor.opacity(0.18))
                .frame(width: 220, height: 220)
                .blur(radius: 16)
                .offset(x: 250, y: -90)

            Circle()
                .stroke(Color.white.opacity(0.05), lineWidth: 26)
                .frame(width: 170, height: 170)
                .offset(x: 290, y: 180)
        }
        .allowsHitTesting(false)
    }
}
