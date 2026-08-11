import SwiftUI
import OctopusDomain
import OctopusDesignSystem
import OctopusNavigation

public struct SeriesDependencies {
    public let playlists: PlaylistRepository
    public let series: SeriesRepository
    public let favorites: FavoritesRepository
    public let progress: PlaybackProgressRepository
    /// Kilit açıkken yetişkin diziler katalogdan gizlenir.
    public let parental: ParentalControlling

    public init(
        playlists: PlaylistRepository,
        series: SeriesRepository,
        favorites: FavoritesRepository,
        progress: PlaybackProgressRepository,
        parental: ParentalControlling = OpenParentalControl()
    ) {
        self.playlists = playlists
        self.series = series
        self.favorites = favorites
        self.progress = progress
        self.parental = parental
    }
}

/// Dizi kataloğu: kategori şeridi + afiş ızgarası.
public struct SeriesScreen: View {

    @StateObject private var viewModel: SeriesViewModel
    @EnvironmentObject private var router: AppRouter

    private let columns = [
        GridItem(.adaptive(minimum: 104), spacing: Theme.Spacing.md)
    ]

    public init(dependencies: SeriesDependencies) {
        _viewModel = StateObject(wrappedValue: SeriesViewModel(dependencies: dependencies))
    }

    public var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                if !viewModel.categories.isEmpty && !viewModel.isSearching {
                    SeriesCategoryStrip(
                        categories: viewModel.categories,
                        selectedID: viewModel.selectedCategoryID,
                        onSelect: { id in Task { await viewModel.selectCategory(id) } }
                    )
                }
                content
            }
        }
        .navigationTitle("Diziler")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Dizi ara"
        )
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ScrollView { PosterGridSkeleton() }

        case .failed(let error):
            ErrorStateView(error: error) { Task { await viewModel.load() } }

        case .loaded:
            if viewModel.series.isEmpty {
                EmptyStateView(
                    icon: viewModel.isSearching ? "magnifyingglass" : "rectangle.stack",
                    title: viewModel.isSearching ? "Sonuç yok" : "Dizi yok",
                    message: viewModel.isSearching
                        ? "Farklı bir arama dene."
                        : "Bu kaynakta dizi paketi bulunmuyor olabilir. Kaynağı güncellemeyi dene.",
                    actionTitle: viewModel.isSearching ? nil : "Ayarlar'a git",
                    action: viewModel.isSearching ? nil : { router.push(.about) }
                )
            } else {
                grid
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Theme.Spacing.lg) {
                ForEach(viewModel.series) { item in
                    SeriesPosterCell(
                        series: item,
                        isFavorite: viewModel.isFavorite(item),
                        onTap: { router.push(.seriesDetail(item.id)) },
                        onToggleFavorite: { Task { await viewModel.toggleFavorite(item) } }
                    )
                    .task { await viewModel.loadMoreIfNeeded(currentItem: item) }
                }
            }
            .padding(Theme.Spacing.md)

            if viewModel.canLoadMore && !viewModel.isSearching {
                ProgressView()
                    .tint(Theme.Palette.accent)
                    .padding(Theme.Spacing.lg)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 52)
        }
    }
}
