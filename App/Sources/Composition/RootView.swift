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
struct RootView: View {

    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var router: AppRouter

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

    private var tabs: some View {
        TabView(selection: $router.selectedTab) {
            tab(.home, title: "Ana Sayfa", icon: "house.fill") {
                HomeScreen(dependencies: container.makeHomeDependencies())
            }
            tab(.live, title: "Canlı TV", icon: "tv.fill") {
                LiveScreen(dependencies: container.makeLiveDependencies())
            }
            tab(.movies, title: "Filmler", icon: "film.fill") {
                MoviesScreen(dependencies: container.makeVODDependencies())
            }
            tab(.series, title: "Diziler", icon: "rectangle.stack.fill") {
                SeriesScreen(dependencies: container.makeSeriesDependencies())
            }
            tab(.search, title: "Ara", icon: "magnifyingglass") {
                SearchScreen(dependencies: container.makeSearchDependencies())
            }
            tab(.settings, title: "Ayarlar", icon: "gearshape.fill") {
                SettingsScreen(dependencies: container.makeSettingsDependencies())
            }
        }
    }

    /// Her sekme kendi `NavigationStack`'ine sahiptir; sekme değişince yığın korunur.
    private func tab<Content: View>(
        _ item: AppTab,
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack(path: router.binding(for: item)) {
            content()
                .navigationDestination(for: AppRoute.self) { route in
                    destination(for: route)
                }
        }
        .tabItem { Label(title, systemImage: icon) }
        .tag(item)
    }

    // MARK: - Route → Ekran eşlemesi
    //
    // Feature'lar birbirini import edemediği için bu eşleme burada yapılır.
    // Yeni bir ekran eklemek = `AppRoute`'a bir case + buraya bir satır.

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .channels:
            LiveScreen(dependencies: container.makeLiveDependencies())
        case .movieDetail(let id):
            MovieDetailView(
                movieID: id,
                dependencies: container.makeVODDependencies()
            )
        case .categoryList:
            MoviesScreen(dependencies: container.makeVODDependencies())
        case .seriesDetail(let id):
            SeriesDetailView(
                seriesID: id,
                dependencies: container.makeSeriesDependencies()
            )
        case .seasonEpisodes(let seriesID, _):
            // Sezon seçimi detay ekranının içinde yapılır; doğrudan sezona
            // gelen bir bağlantı da diziyi açar.
            SeriesDetailView(
                seriesID: seriesID,
                dependencies: container.makeSeriesDependencies()
            )
        case .playlistManager:
            PlaylistManagerView(dependencies: container.makeSettingsDependencies())
        case .favorites:
            FavoritesScreen(dependencies: container.makeFavoritesDependencies())
        case .about:
            SettingsScreen(dependencies: container.makeSettingsDependencies())
        }
    }

    @ViewBuilder
    private func sheetContent(for sheet: AppSheet) -> some View {
        switch sheet {
        case .addPlaylist, .editPlaylist:
            // Kaynak yönetiminden de onboarding'den de aynı form açılır.
            NavigationStack {
                AddPlaylistView(dependencies: container.makeOnboardingDependencies()) {
                    router.dismissSheet()
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Vazgeç") { router.dismissSheet() }
                            .tint(Theme.Palette.accent)
                    }
                }
            }
        case .trackSelection, .parentalLock:
            SettingsScreen(dependencies: container.makeSettingsDependencies())
        }
    }
}
