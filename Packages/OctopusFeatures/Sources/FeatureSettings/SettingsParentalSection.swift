import SwiftUI
import OctopusDomain
import OctopusDesignSystem
import OctopusNavigation

extension SettingsScreen {

    var parentalSection: some View {
        section("Ebeveyn Kontrolleri") {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(parentalStatusColor)
                    .frame(width: 42, height: 42)
                    .background(
                        parentalStatusColor.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Ebeveyn Kontrolleri")
                        .font(Theme.Typography.sectionTitle)
                        .foregroundColor(Theme.Palette.textPrimary)

                    Text("Yetişkin içerik ve seçtiğin kategoriler PIN ile korunur.")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: Theme.Spacing.xs) {
                        Circle()
                            .fill(parentalStatusColor)
                            .frame(width: 7, height: 7)
                        Text(
                            AppLocalization.localized(
                                parentalStatusTitle,
                                locale: language.locale
                            )
                        )
                            .font(Theme.Typography.badge)
                            .foregroundColor(parentalStatusColor)
                    }
                    .padding(.top, Theme.Spacing.xs)
                }
            }
            .settingsSurface()

            SettingsRow(
                icon: viewModel.isProtectedContentUnlocked ? "shield.slash.fill" : "shield.fill",
                title: protectionTitle,
                detail: protectionDetail
            ) {
                if viewModel.isProtectedContentUnlocked {
                    Task { await viewModel.lockProtectedContent() }
                } else {
                    opensCategoriesAfterUnlock = false
                    isEnteringPIN = true
                }
            }

            SettingsRow(
                icon: "number.square.fill",
                title: "PIN'i değiştir",
                detail: "Ebeveyn kontrolü PIN'ini güncelle"
            ) {
                isChangingPIN = true
            }

            SettingsRow(
                icon: "rectangle.3.group.fill",
                title: "Korumalı kategorileri yönet",
                detail: categoryManagementDetail
            ) {
                if viewModel.isProtectedContentUnlocked {
                    isManagingCategories = true
                } else {
                    opensCategoriesAfterUnlock = true
                    isEnteringPIN = true
                }
            }
        }
    }

    private var protectionTitle: String {
        if viewModel.isProtectedContentUnlocked { return "Korunmayı şimdi etkinleştir" }
        return "Yetişkin içerik kilidini geçici aç"
    }

    private var protectionDetail: String {
        if viewModel.isProtectedContentUnlocked {
            return "Yetişkin içerik bu oturumda görünür"
        }
        return "Yetişkin içerik gizli; açmak için PIN gerekir"
    }

    private var parentalStatusTitle: String {
        viewModel.isProtectedContentUnlocked
            ? "İÇERİK BU OTURUMDA AÇIK"
            : "KORUMA ETKİN"
    }

    private var parentalStatusColor: Color {
        viewModel.isProtectedContentUnlocked ? Theme.Palette.warning : Theme.Palette.success
    }

    private var categoryManagementDetail: String {
        let hidden = viewModel.hiddenCategoryKeys.count
        if !viewModel.isProtectedContentUnlocked { return "Önce ebeveyn kontrolü PIN'ini gir" }
        return hidden == 0
            ? "Tüm kategoriler görünür"
            : language.localized("%ld kategori gizli", hidden)
    }
}
