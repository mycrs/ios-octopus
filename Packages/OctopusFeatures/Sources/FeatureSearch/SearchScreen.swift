import SwiftUI
import OctopusDomain
import OctopusDesignSystem
import OctopusNavigation

public struct SearchDependencies {
    public let channels: ChannelRepository
    public let vod: VODRepository
    public let series: SeriesRepository

    public init(
        channels: ChannelRepository,
        vod: VODRepository,
        series: SeriesRepository
    ) {
        self.channels = channels
        self.vod = vod
        self.series = series
    }
}

/// Birleşik arama: kanal + film + dizi tek listede.
/// Faz 4'te doldurulacak (FTS5 sorgusu Data katmanında).
public struct SearchScreen: View {

    private let dependencies: SearchDependencies
    @EnvironmentObject private var router: AppRouter

    public init(dependencies: SearchDependencies) {
        self.dependencies = dependencies
    }

    public var body: some View {
        EmptyStateView(
            icon: "magnifyingglass",
            title: "Arama",
            message: "Kanal, film ve dizide birleşik arama Faz 4'te gelecek."
        )
        .background(Theme.Palette.background)
    }
}
