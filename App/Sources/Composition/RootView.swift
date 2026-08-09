import SwiftUI
import OctopusDomain
import OctopusDesignSystem
import OctopusNavigation
import FeatureOnboarding
import FeatureHome
import FeatureLive
import FeatureVOD
import FeatureSeries
import FeatureSearch
import FeatureFavorites
import FeaturePlayer
import FeatureSettings

/// Kök ekran yapısı: onboarding mi, sekmeler mi?
///
/// Bu dosya yalnızca **iskelet kurar**. Ekranların içeriği feature modüllerinde.
/// Route → ekran eşlemesi `RootView+Routing.swift` içinde bir `extension`.
struct RootView: View {

    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var router: AppRouter

    var body: some View {
        ZStack {
            // Uygulama genelinde taban renk. Tek tek ekranların arka planı
            // eksik kalsa bile sistem siyahı görünmez.
            Theme.Palette.background.ignoresSafeArea()

            if let gate = container.appConfig?.gate, gate.isBlocking {
                // Panel bakım moduna aldı: içeriğe erişim kesilir ama
                // kullanıcı sorunun geçici olduğunu ve nereye başvuracağını bilir.
                MaintenanceGateView(
                    message: maintenanceMessage(from: gate),
                    contact: container.appConfig?.contact ?? .empty,
                    onRetry: { Task { await container.refreshRemoteConfig() } }
                )
            } else if router.needsOnboarding {
                OnboardingScreen(dependencies: container.makeOnboardingDependencies())
            } else {
                mainContent
            }
        }
        // Marka rengi: kullanıcı seçimi > bayi paneli > uygulama varsayılanı.
        .tint(container.themeController.accent)
        .environment(\.brandColor, container.themeController.accent)
        // Ayarlar ekranı renk seçimini buradan okur ve değiştirir.
        .environmentObject(container.themeController)
        // Oynatıcı tercihleri de aynı yoldan: Ayarlar düzenler, motorlar okur.
        .environmentObject(container.playbackPreferences)
        // Oynatıcı tam ekran sunulur — gezinme yığınına girmez,
        // böylece hangi ekrandan açılırsa açılsın davranışı aynıdır.
        .fullScreenCover(item: $router.player) { presentation in
            PlayerScreen(
                presentation: presentation,
                dependencies: container.makePlayerDependencies()
            )
            .environmentObject(router)
        }
        .sheet(item: $router.sheet) { sheet in
            sheetContent(for: sheet)
                .environmentObject(router)
        }
    }

    // MARK: - Ana içerik

    /// Sekmeler ve üstünde (varsa) panel duyurusu.
    private var mainContent: some View {
        VStack(spacing: 0) {
            if let announcement = container.visibleAnnouncement {
                AnnouncementBanner(announcement: announcement) {
                    container.dismissAnnouncement()
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.sm)
            }
            tabs
        }
    }

    private func maintenanceMessage(from gate: ServiceGate) -> String? {
        if case .maintenance(let message) = gate { return message }
        return nil
    }

    // MARK: - Sekmeler

    /// ⚠️ Tam olarak 5 sekme: iOS altıncı sekmeden itibaren gezinme
    /// çubuğunu otomatik olarak "Daha Fazla" listesine çeviriyor.
    /// Referansta da arama ve ayarlar sekme değil, üst bar ikonuydu —
    /// burada da öyle (bkz. `tab(_:content:)`).
    private var tabs: some View {
        TabView(selection: $router.selectedTab) {
            tab(.home) {
                HomeScreen(dependencies: container.makeHomeDependencies())
            }
            tab(.live) {
                LiveScreen(dependencies: container.makeLiveDependencies())
            }
            tab(.movies) {
                MoviesScreen(dependencies: container.makeVODDependencies())
            }
            tab(.series) {
                SeriesScreen(dependencies: container.makeSeriesDependencies())
            }
            tab(.favorites) {
                FavoritesScreen(dependencies: container.makeFavoritesDependencies())
            }
        }
    }

    /// Her sekme kendi `NavigationStack`'ine sahiptir; sekme değişince yığın korunur.
    ///
    /// Başlık ve ikon `AppTab`'ten okunur — ayarlar ekranındaki açılış
    /// tercihiyle aynı kaynaktan, ikisi ayrı düşmesin.
    ///
    /// Arama ve ayarlar ikonu yalnızca sekmenin **kök** ekranında görünür;
    /// bir detaya girildiğinde iOS bu toolbar'ı otomatik gizler ve o
    /// ekranın kendi eylemlerini (ör. favori düğmesi) gösterir.
    private func tab<Content: View>(
        _ item: AppTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack(path: router.binding(for: item)) {
            content()
                .navigationDestination(for: AppRoute.self) { route in
                    destination(for: route)
                        // ⚠️ Açıkça görünür: Canlı TV kök ekranı gezinme
                        // çubuğunu gizliyor (video üst kenara yapışsın diye).
                        // Bu olmadan oradan açılan ekranlarda geri düğmesi
                        // kaybolur ve kullanıcı sıkışırdı.
                        .toolbar(.visible, for: .navigationBar)
                }
                .toolbar {
                    // ⚠️ Kareyle görüldü: Filmler ve Diziler'de **iki arama**
                    // birden vardı — üst bardaki bu ikon (birleşik aramaya
                    // gider) ve ekranın kendi arama alanı. Kullanıcı hangisinin
                    // ne aradığını bilemiyordu. Kendi araması olan sekmelerde
                    // ikon gösterilmiyor.
                    if item.showsGlobalSearchAction {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button {
                                router.push(.search, in: item)
                            } label: {
                                Image(systemName: "magnifyingglass")
                            }
                            .accessibilityLabel("Ara")
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            router.push(.about, in: item)
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Ayarlar")
                    }
                }
        }
        .tabItem { Label(item.title, systemImage: item.icon) }
        .tag(item)
    }

}
