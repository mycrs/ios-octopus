import SwiftUI
import OctopusDomain
import OctopusDesignSystem
import OctopusNavigation

public struct VODDependencies {
    public let vod: VODRepository
    public let favorites: FavoritesRepository
    public let progress: PlaybackProgressRepository

    public init(
        vod: VODRepository,
        favorites: FavoritesRepository,
        progress: PlaybackProgressRepository
    ) {
        self.vod = vod
        self.favorites = favorites
        self.progress = progress
    }
}

/// Filmler: kategori ızgarası → afiş listesi → detay.
/// Faz 7'de doldurulacak.
public struct MoviesScreen: View {

    private let dependencies: VODDependencies
    @EnvironmentObject private var router: AppRouter

    public init(dependencies: VODDependencies) {
        self.dependencies = dependencies
    }

    public var body: some View {
        EmptyStateView(
            icon: "film",
            title: "Filmler",
            message: "Afiş ızgarası ve film detay ekranı Faz 7'de gelecek."
        )
        .background(Theme.Palette.background)
    }
}
