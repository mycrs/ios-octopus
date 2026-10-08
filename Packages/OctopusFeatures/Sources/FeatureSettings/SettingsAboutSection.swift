import SwiftUI
import OctopusDesignSystem

extension SettingsScreen {
    var aboutSection: some View {
        section("Uygulama") {
            AppPolicyLinks()
                .settingsSurface()

            HStack {
                Text("Sürüm")
                    .font(Theme.Typography.rowSubtitle)
                    .foregroundColor(Theme.Palette.textSecondary)
                Spacer()
                Text(viewModel.appVersion)
                    .font(Theme.Typography.rowSubtitle)
                    .foregroundColor(Theme.Palette.textTertiary)
            }
            .settingsSurface()

            // Örnek filmler ile kullanıcının kendi yayın kaynağını ayırır.
            Text(
                AppLocalization.localized(
                    "Ticari kanal aboneliği sağlanmaz. Açık lisanslı örnek filmleri deneyebilir veya kullanım iznin olan kendi kaynağını ekleyebilirsin.",
                    locale: language.locale
                )
            )
            .font(Theme.Typography.caption)
            .foregroundColor(Theme.Palette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Theme.Spacing.xs)
        }
    }

}
