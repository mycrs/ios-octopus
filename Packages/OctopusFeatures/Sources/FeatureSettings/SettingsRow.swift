import SwiftUI
import OctopusDesignSystem

/// Ayarlar ekranındaki tekil satır: ikon, başlık, isteğe bağlı alt metin.
struct SettingsRow: View {

    let icon: String
    let title: String
    var detail: String?
    let action: () -> Void
    @Environment(\.locale) private var locale
    @Environment(\.brandColor) private var brandColor

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(brandColor)
                    .frame(width: 34, height: 34)
                    .background(
                        brandColor.opacity(0.13),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )

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
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.Palette.textTertiary)
            }
            .settingsSurface()
        }
        .buttonStyle(.plain)
    }
}

extension View {
    func settingsSurface() -> some View {
        modifier(SettingsSurfaceModifier())
    }
}

private struct SettingsSurfaceModifier: ViewModifier {
    @Environment(\.brandColor) private var brandColor

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            .background(
                LinearGradient(
                    colors: [Theme.Palette.surfaceElevated.opacity(0.78), Theme.Palette.surface],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .strokeBorder(brandColor.opacity(0.10), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.12), radius: 12, y: 6)
    }
}
