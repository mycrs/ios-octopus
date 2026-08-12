import SwiftUI
import OctopusDomain
import OctopusDesignSystem
import OctopusNavigation

/// `SettingsScreen`'in bölümleri — ayrı dosyada, tek dosya 200 satırı
/// geçmesin diye (bkz. CLAUDE.md stil kuralı).
extension SettingsScreen {

    var sourceSection: some View {
        section("Kaynak") {
            SettingsRow(
                icon: "antenna.radiowaves.left.and.right",
                title: viewModel.activePlaylistName ?? "Kaynak seçilmedi",
                detail: viewModel.lastSyncedText
            ) {
                router.push(.playlistManager)
            }

            SettingsRow(icon: "arrow.clockwise", title: "Şimdi güncelle") {
                Task { await viewModel.resyncActivePlaylist() }
            }

            if viewModel.playlistCount > 1 {
                Text("\(viewModel.playlistCount) kaynak kayıtlı")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Palette.textTertiary)
            }
        }
    }

    var appearanceSection: some View {
        section("Görünüm") {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Vurgu rengi")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Palette.textSecondary)

                HStack(spacing: Theme.Spacing.md) {
                    ForEach(Theme.BrandColor.allCases, id: \.self) { option in
                        Button {
                            theme.select(option)
                        } label: {
                            Circle()
                                .fill(option.color)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            theme.selection == option
                                                ? Theme.Palette.textPrimary
                                                : Color.clear,
                                            lineWidth: 2
                                        )
                                )
                        }
                        .accessibilityLabel(option.rawValue)
                    }
                }

                // Uzaktan marka varsa "Varsayılan" onun rengini kullanır.
                if let resellerName = theme.resellerName {
                    Text("Varsayılan görünüm \(resellerName) markasına uyarlanıyor.")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Palette.textTertiary)
                }
            }
            .settingsSurface()
        }
    }

    var languageSection: some View {
        section("Dil") {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "globe")
                    .foregroundColor(brandColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text("Uygulama dili")
                        .font(Theme.Typography.rowTitle)
                        .foregroundColor(Theme.Palette.textPrimary)

                    Text(
                        language.selection == .system
                            ? language.localized(
                                "Cihaz diline göre otomatik: %@",
                                language.resolvedLanguageTitle
                            )
                            : language.localized("Seçimin anında uygulanır")
                    )
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Palette.textTertiary)
                }

                Spacer(minLength: Theme.Spacing.sm)

                Picker(
                    "Dil",
                    selection: Binding(
                        get: { language.selection },
                        set: { language.select($0) }
                    )
                ) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(LocalizedStringKey(option.title)).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(brandColor)
            }
            .settingsSurface()
        }
    }

    var startupSection: some View {
        section("Açılış") {
            // Menü seçici: dört başlık segment'e sığmıyor, dar ekranda
            // "Ana Say…" gibi kırpılıyordu.
            Picker(selection: $router.startupTab) {
                ForEach(AppTab.startupOptions) { tab in
                    Label {
                        Text(LocalizedStringKey(tab.title))
                    } icon: {
                        Image(systemName: tab.icon)
                    }
                    .tag(tab)
                }
            } label: {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "arrow.right.to.line")
                        .foregroundColor(Theme.Palette.accent)
                        .frame(width: 24)
                    Text("Açılış ekranı")
                        .font(Theme.Typography.rowTitle)
                        .foregroundColor(Theme.Palette.textPrimary)
                }
            }
            .pickerStyle(.menu)
            .settingsSurface()
        }
    }

    var parentalSection: some View {
        section("İçerik kilidi") {
            SettingsRow(
                icon: viewModel.isProtectedContentUnlocked ? "lock.open.fill" : "lock.fill",
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
                detail: "Mevcut PIN gerekir"
            ) {
                isChangingPIN = true
            }

            SettingsRow(
                icon: "rectangle.3.group.fill",
                title: "Kategorileri yönet",
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
        if viewModel.isProtectedContentUnlocked { return "Şimdi kilitle" }
        return "Kilidi geçici aç"
    }

    private var protectionDetail: String {
        if viewModel.isProtectedContentUnlocked {
            return "Hassas içerikler bu oturumda görünür"
        }
        return "Hassas içerikler PIN ile korunuyor"
    }

    private var categoryManagementDetail: String {
        let hidden = viewModel.hiddenCategoryKeys.count
        if !viewModel.isProtectedContentUnlocked { return "Önce içerik kilidini aç" }
        return hidden == 0
            ? "Tüm kategoriler görünür"
            : language.localized("%ld kategori gizli", hidden)
    }

    var dataSection: some View {
        section("Veriler") {
            SettingsRow(icon: "clock.arrow.circlepath", title: "İzleme geçmişini sil") {
                confirmingAction = .history
            }
            SettingsRow(icon: "play.slash", title: "Kaldığın yer bilgilerini sil") {
                confirmingAction = .progress
            }
            // Onay istemiyor: veri kaybı yok, görseller yeniden indirilir.
            SettingsRow(
                icon: "photo.on.rectangle",
                title: "Görsel önbelleğini temizle",
                detail: "Afiş ve logolar yeniden indirilir"
            ) {
                Task { await viewModel.clearImageCache() }
            }
        }
    }

    var supportSection: some View {
        section("Destek") {
            ContactLinksView(contact: contact)
        }
    }

    var aboutSection: some View {
        section("Uygulama") {
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
        }
    }

    func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(AppLocalization.localized(title, locale: language.locale))
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.7)
                .foregroundColor(Theme.Palette.textSecondary)
                .padding(.horizontal, Theme.Spacing.xs)
            content()
        }
    }
}
