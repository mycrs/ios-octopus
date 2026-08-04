import SwiftUI
import OctopusDomain
import OctopusDesignSystem
import OctopusNavigation

public struct SeriesDependencies {
    public let series: SeriesRepository
    public let favorites: FavoritesRepository
    public let progress: PlaybackProgressRepository

    public init(
        series: SeriesRepository,
        favorites: FavoritesRepository,
        progress: PlaybackProgressRepository
    ) {
        self.series = series
        self.favorites = favorites
        self.progress = progress
    }
}

/// Diziler: dizi ızgarası → sezon seçimi → bölüm listesi.
/// Faz 7'de doldurulacak.
public struct SeriesScreen: View {

    private let dependencies: SeriesDependencies
    @EnvironmentObject private var router: AppRouter

    public init(dependencies: SeriesDependencies) {
        self.dependencies = dependencies
    }

    public var body: some View {
        EmptyStateView(
            icon: "rectangle.stack",
            title: "Diziler",
            message: "Sezon/bölüm ağacı ve devam etme rozetleri Faz 7'de gelecek."
        )
        .background(Theme.Palette.background)
    }
}
