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
            LoadingStateView(message: "Diziler yükleniyor")

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
                    action: viewModel.isSearching ? nil : { router.switchTab(to: .settings) }
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
    }
}

private struct SeriesPosterCell: View {

    let series: Series
    let isFavorite: Bool
    let onTap: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                GridPosterView(url: series.posterURL)
                    .overlay(alignment: .topTrailing) {
                        if isFavorite {
                            Image(systemName: "heart.fill")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Palette.live)
                                .padding(Theme.Spacing.xs)
                                .background(.ultraThinMaterial, in: Circle())
                                .padding(Theme.Spacing.xs)
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        RatingBadge(rating: series.rating)
                            .padding(Theme.Spacing.xs)
                    }

                Text(series.title)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    // Hücre genişliğini doldur; sabit genişlik iPad'de
                    // başlıkları afişten dar bırakıyordu.
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onToggleFavorite()
            } label: {
                Label(
                    isFavorite ? "Favorilerden çıkar" : "Favorilere ekle",
                    systemImage: isFavorite ? "heart.slash" : "heart"
                )
            }
        }
    }
}

/// Dizi ekranının kategori şeridi.
///
/// `FeatureVOD`'daki şeritle aynı görünür ama feature'lar birbirini import
/// edemez. Ortak bir bileşen `OctopusDesignSystem`'e taşınabilirdi; şimdilik
/// iki küçük kopya, modül sınırını delmekten daha ucuz.
private struct SeriesCategoryStrip: View {

    let categories: [MediaCategory]
    let selectedID: MediaCategory.ID?
    let onSelect: (MediaCategory.ID?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                chip(title: "Tümü", isSelected: selectedID == nil) { onSelect(nil) }

                ForEach(categories) { category in
                    chip(title: category.name, isSelected: selectedID == category.id) {
                        onSelect(category.id)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
        }
    }

    private func chip(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.caption)
                .lineLimit(1)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(isSelected ? Theme.Palette.accentMuted : Theme.Palette.surface)
                .foregroundColor(isSelected ? Theme.Palette.accent : Theme.Palette.textSecondary)
                .clipShape(Capsule())
        }
    }
}
