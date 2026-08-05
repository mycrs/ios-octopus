import SwiftUI
import OctopusDesignSystem
import OctopusNavigation
import FeatureOnboarding
import FeatureHome
import FeatureLive
import FeatureVOD
import FeatureSeries
import FeatureSearch
import FeaturePlayer
import FeatureSettings

/// Kök ekran yapısı: onboarding mi, sekmeler mi?
///
/// Bu dosya yalnızca **iskelet kurar**. Ekranların içeriği feature modüllerinde.
struct RootView: View {

    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        Group {
            if router.needsOnboarding {
                OnboardingScreen(dependencies: container.makeOnboardingDependencies())
            } else {
                tabs
            }
        }
        .tint(Theme.Palette.accent)
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
        case .movieDetail, .categoryList:
            MoviesScreen(dependencies: container.makeVODDependencies())
        case .seriesDetail, .seasonEpisodes:
            SeriesScreen(dependencies: container.makeSeriesDependencies())
        case .playlistManager:
            PlaylistManagerView(dependencies: container.makeSettingsDependencies())
        case .favorites, .about:
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
