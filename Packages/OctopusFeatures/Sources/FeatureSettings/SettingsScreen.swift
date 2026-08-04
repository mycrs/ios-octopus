import SwiftUI
import OctopusDomain
import OctopusDesignSystem
import OctopusNavigation

public struct SettingsDependencies {
    public let playlists: PlaylistRepository
    public let sync: ContentSyncing
    public let progress: PlaybackProgressRepository
    public let history: WatchHistoryRepository

    public init(
        playlists: PlaylistRepository,
        sync: ContentSyncing,
        progress: PlaybackProgressRepository,
        history: WatchHistoryRepository
    ) {
        self.playlists = playlists
        self.sync = sync
        self.progress = progress
        self.history = history
    }
}

/// Ayarlar: kaynak yönetimi, senkronizasyon, ebeveyn kilidi, önbellek temizliği.
/// Faz 3 ve Faz 10'da doldurulacak.
public struct SettingsScreen: View {

    private let dependencies: SettingsDependencies
    @EnvironmentObject private var router: AppRouter

    public init(dependencies: SettingsDependencies) {
        self.dependencies = dependencies
    }

    public var body: some View {
        EmptyStateView(
            icon: "gearshape",
            title: "Ayarlar",
            message: "Kaynak yönetimi, senkronizasyon ve ebeveyn kilidi Faz 3+'ta gelecek.",
            actionTitle: "Kaynakları yönet",
            action: { router.push(.playlistManager) }
        )
        .background(Theme.Palette.background)
    }
}
