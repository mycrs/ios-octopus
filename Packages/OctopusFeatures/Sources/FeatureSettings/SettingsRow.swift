import SwiftUI
import OctopusDesignSystem

/// Ayarlar ekranındaki tekil satır: ikon, başlık, isteğe bağlı alt metin.
struct SettingsRow: View {

    let icon: String
    let title: String
    var detail: String?
    let action: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: icon)
                    .foregroundColor(Theme.Palette.accent)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(AppLocalization.localized(title, locale: locale))
                        .font(Theme.Typography.rowTitle)
                        .foregroundColor(Theme.Palette.textPrimary)
                        .multilineTextAlignment(.leading)

                    if let detail {
                        Text(AppLocalization.localized(detail, locale: locale))
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Palette.textTertiary)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Palette.textTertiary)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
