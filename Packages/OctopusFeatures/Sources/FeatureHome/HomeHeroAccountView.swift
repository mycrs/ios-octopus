import SwiftUI
import OctopusDesignSystem

/// Hero içindeki kullanıcı ve abonelik özetini tek, sakin bir cam yüzeyde sunar.
/// Kaynak adresi veya bağlantı kodu gibi teknik değerler burada gösterilmez.
struct HomeHeroAccountView: View {
    let account: HomeAccount?

    @Environment(\.brandColor) private var brandColor
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ViewBuilder
    var body: some View {
        if let account, account.username != nil || account.expiryDateText != nil {
            accountSurface(account)
        } else {
            Label("İçeriklerin güncel", systemImage: "checkmark.seal.fill")
                .font(Theme.Typography.caption)
                .symbolRenderingMode(.palette)
                .foregroundStyle(Theme.Palette.success, Theme.Palette.textSecondary)
        }
    }

    @ViewBuilder
    private func accountSurface(_ account: HomeAccount) -> some View {
        if usesStackedLayout {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                accountItems(account, usesVerticalDivider: false)
            }
            .modifier(AccountSurfaceStyle())
        } else {
            HStack(spacing: Theme.Spacing.md) {
                accountItems(account, usesVerticalDivider: true)
            }
            .modifier(AccountSurfaceStyle())
        }
    }

    @ViewBuilder
    private func accountItems(
        _ account: HomeAccount,
        usesVerticalDivider: Bool
    ) -> some View {
        if let username = account.username {
            item(
                icon: "person.fill",
                caption: "KULLANICI",
                value: username,
                detail: "Aktif hesap",
                tint: brandColor
            )
        }

        if account.username != nil, account.expiryDateText != nil {
            if usesVerticalDivider {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1, height: 42)
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
            }
        }

        if let expiryDate = account.expiryDateText {
            item(
                icon: "calendar.badge.clock",
                caption: "BİTİŞ TARİHİ",
                value: expiryDate,
                detail: account.expiryText,
                tint: statusColor(for: account)
            )
        }
    }

    private func item(
        icon: String,
        caption: String,
        value: String,
        detail: String?,
        tint: Color
    ) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(AppLocalization.localized(caption, locale: locale))
                    .font(Theme.Typography.badge)
                    .tracking(0.65)
                    .foregroundColor(Theme.Palette.textTertiary)

                Text(value)
                    .font(Theme.Typography.caption.weight(.semibold))
                    .foregroundColor(Theme.Palette.textPrimary)
                    .lineLimit(usesStackedLayout ? 2 : 1)
                    .minimumScaleFactor(0.72)

                if let detail {
                    Text(AppLocalization.localized(detail, locale: locale))
                        .font(Theme.Typography.badge)
                        .foregroundColor(tint.opacity(0.88))
                        .lineLimit(usesStackedLayout ? 2 : 1)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func statusColor(for account: HomeAccount) -> Color {
        switch account.urgency {
        case .normal: return Theme.Palette.success
        case .soon: return Theme.Palette.warning
        case .expired: return Theme.Palette.error
        }
    }

    /// Hero üst seviyede erişilebilirlik boyutunu `xxxLarge` ile sınırlar.
    /// Bu nedenle yalnızca `isAccessibilitySize` kontrolü kullanılsaydı hesap
    /// satırı yatay kalıp metinleri keserdi; büyük standart boyutlarda da dizilir.
    private var usesStackedLayout: Bool {
        dynamicTypeSize >= .xxLarge
    }
}

private struct AccountSurfaceStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                Color.white.opacity(0.045),
                in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            }
    }
}
