import SwiftUI
import OctopusDomain
import OctopusDesignSystem
import OctopusNavigation

public struct HomeDependencies {
    public let playlists: PlaylistRepository
    public let channels: ChannelRepository
    public let vod: VODRepository
    public let series: SeriesRepository
    public let progress: PlaybackProgressRepository
    public let history: WatchHistoryRepository

    public init(
        playlists: PlaylistRepository,
        channels: ChannelRepository,
        vod: VODRepository,
        series: SeriesRepository,
        progress: PlaybackProgressRepository,
        history: WatchHistoryRepository
    ) {
        self.playlists = playlists
        self.channels = channels
        self.vod = vod
        self.series = series
        self.progress = progress
        self.history = history
    }
}

/// Ana sayfa: "İzlemeye devam et", "Son eklenenler", "Son izlenen kanallar" rafları.
/// Faz 8'de doldurulacak.
public struct HomeScreen: View {

    private let dependencies: HomeDependencies
    @EnvironmentObject private var router: AppRouter

    public init(dependencies: HomeDependencies) {
        self.dependencies = dependencies
    }

    public var body: some View {
        EmptyStateView(
            icon: "house",
            title: "Ana sayfa",
            message: "İzlemeye devam et ve son eklenenler rafları Faz 8'de gelecek."
        )
        .background(Theme.Palette.background)
    }
}
