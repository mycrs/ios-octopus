import SwiftUI
import OctopusDomain
import OctopusDesignSystem
import OctopusNavigation

/// Bu feature'ın ihtiyaç duyduğu her şey.
///
/// ⚠️ KALIP: Her feature bağımlılıklarını **protokol** olarak burada beyan eder.
/// Somut tipleri (`XtreamContentProvider`, `PlaylistRepositoryImpl`…) görmez.
/// Bağlama işi yalnızca `AppContainer`'da yapılır.
/// Test yazarken bu struct sahte implementasyonlarla doldurulur.
public struct OnboardingDependencies {
    public let playlists: PlaylistRepository
    public let sync: ContentSyncing

    public init(playlists: PlaylistRepository, sync: ContentSyncing) {
        self.playlists = playlists
        self.sync = sync
    }
}

/// Kaynak ekleme akışının giriş noktası.
/// Faz 3: Xtream/M3U form + doğrulama + ilk senkronizasyon ilerlemesi.
public struct OnboardingScreen: View {

    private let dependencies: OnboardingDependencies
    @EnvironmentObject private var router: AppRouter

    public init(dependencies: OnboardingDependencies) {
        self.dependencies = dependencies
    }

    public var body: some View {
        EmptyStateView(
            icon: "antenna.radiowaves.left.and.right",
            title: "Kaynak ekle",
            message: "Xtream hesabını veya M3U bağlantını ekleyerek başla.",
            actionTitle: "Kaynak ekle",
            action: { router.present(.addPlaylist) }
        )
        .background(Theme.Palette.background)
    }
}
