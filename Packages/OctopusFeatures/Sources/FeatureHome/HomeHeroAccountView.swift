import SwiftUI
import OctopusDesignSystem

/// Hero içindeki kullanıcıya anlamlı hesap özeti.
/// Kaynak adresi veya bağlantı kodu gibi teknik değerler burada gösterilmez.
struct HomeHeroAccountView: View {
    let account: HomeAccount?
    @Environment(\.brandColor) private var brandColor
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ViewBuilder
    var body: some View {
        if let account, account.username != nil || account.expiryDateText != nil {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: Theme.Spacing.sm) {
                    accountTiles(account)
                }
            } else {
                HStack(spacing: Theme.Spacing.sm) {
                    accountTiles(account)
                }
            }
        } else {
            Label("İçeriklerin güncel", systemImage: "checkmark.seal.fill")
                .font(Theme.Typography.caption)
                .symbolRenderingMode(.palette)
                .foregroundStyle(Theme.Palette.success, Theme.Palette.textSecondary)
        }
    }

    @ViewBuilder
    private func accountTiles(_ account: HomeAccount) -> some View {
        if let username = account.username {
            tile(
                icon: "person.fill",
                caption: "KULLANICI",
                value: username,
                detail: "Aktif hesap",
                tint: brandColor
            )
        }

        if let expiryDate = account.expiryDateText {
            tile(
                icon: "calendar.badge.clock",
                caption: "BİTİŞ TARİHİ",
                value: expiryDate,
                detail: account.expiryText,
                tint: statusColor(for: account)
            )
        }
    }

    private func tile(
        icon: String,
        caption: String,
        value: String,
        detail: String?,
        tint: Color
    ) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(AppLocalization.localized(caption, locale: locale))
                    .font(Theme.Typography.badge)
                    .tracking(0.7)
                    .foregroundColor(Theme.Palette.textTertiary)

                Text(value)
                    .font(Theme.Typography.caption.weight(.semibold))
                    .foregroundColor(Theme.Palette.textPrimary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(0.72)

                if let detail {
                    Text(AppLocalization.localized(detail, locale: locale))
                        .font(Theme.Typography.badge)
                        .foregroundColor(tint.opacity(0.9))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func statusColor(for account: HomeAccount) -> Color {
        switch account.urgency {
        case .normal: return Theme.Palette.success
        case .soon: return Theme.Palette.warning
        case .expired: return Theme.Palette.error
        }
    }
}
