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

// MARK: - Route → Ekran eşlemesi
//
// Feature'lar birbirini import edemediği için bu eşleme burada yapılır.
// Yeni bir ekran eklemek = `AppRoute`'a bir case + buraya bir satır.

extension RootView {

    @ViewBuilder
    func destination(for route: AppRoute) -> some View {
        switch route {
        case .channels:
            LiveScreen(dependencies: container.makeLiveDependencies())
        case .channelGuide(let id):
            ChannelGuideView(
                channelID: id,
                dependencies: container.makeLiveDependencies()
            )
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
        case .search:
            SearchScreen(dependencies: container.makeSearchDependencies())
        case .about:
            SettingsScreen(dependencies: container.makeSettingsDependencies())
        }
    }

    @ViewBuilder
    func sheetContent(for sheet: AppSheet) -> some View {
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
