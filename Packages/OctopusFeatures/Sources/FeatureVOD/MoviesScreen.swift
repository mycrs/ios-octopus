import SwiftUI
import OctopusDomain
import OctopusDesignSystem
import OctopusNavigation

public struct VODDependencies {
    public let playlists: PlaylistRepository
    public let vod: VODRepository
    public let favorites: FavoritesRepository
    public let progress: PlaybackProgressRepository
    /// Kilit açıkken yetişkin filmler katalogdan gizlenir.
    public let parental: ParentalControlling

    public init(
        playlists: PlaylistRepository,
        vod: VODRepository,
        favorites: FavoritesRepository,
        progress: PlaybackProgressRepository,
        parental: ParentalControlling = OpenParentalControl()
    ) {
        self.playlists = playlists
        self.vod = vod
        self.favorites = favorites
        self.progress = progress
        self.parental = parental
    }
}

/// Film kataloğu: kategori şeridi + afiş ızgarası.
public struct MoviesScreen: View {

    @StateObject private var viewModel: MoviesViewModel
    @EnvironmentObject private var router: AppRouter

    /// Esnek sütun sayısı: iPhone'da 3, iPad'de daha fazla afiş sığar.
    private let columns = [
        GridItem(.adaptive(minimum: 104), spacing: Theme.Spacing.md)
    ]

    public init(dependencies: VODDependencies) {
        _viewModel = StateObject(wrappedValue: MoviesViewModel(dependencies: dependencies))
    }

    public var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                if !viewModel.categories.isEmpty && !viewModel.isSearching {
                    MediaCategoryStrip(
                        categories: viewModel.categories,
                        selectedID: viewModel.selectedCategoryID,
                        onSelect: { id in Task { await viewModel.selectCategory(id) } }
                    )
                }
                content
            }
        }
        .navigationTitle("Filmler")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Film ara"
        )
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingStateView(message: "Filmler yükleniyor")

        case .failed(let error):
            ErrorStateView(error: error) { Task { await viewModel.load() } }

        case .loaded:
            if viewModel.movies.isEmpty {
                // Aramada çıkış yolu kullanıcının elinde (sorguyu değiştirir);
                // katalog boşsa değil — o yüzden oraya bir eylem konuyor.
                EmptyStateView(
                    icon: viewModel.isSearching ? "magnifyingglass" : "film",
                    title: viewModel.isSearching ? "Sonuç yok" : "Film yok",
                    message: viewModel.isSearching
                        ? "Farklı bir arama dene."
                        : "Bu kaynakta film paketi bulunmuyor olabilir. Kaynağı güncellemeyi dene.",
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
                ForEach(viewModel.movies) { movie in
                    MoviePosterCell(
                        movie: movie,
                        isFavorite: viewModel.isFavorite(movie),
                        onTap: { router.push(.movieDetail(movie.id)) },
                        onToggleFavorite: { Task { await viewModel.toggleFavorite(movie) } }
                    )
                    .task {
                        // Sona yaklaşınca sonraki sayfa yüklenir; kullanıcı
                        // kaydırırken duraklama olmaz.
                        await viewModel.loadMoreIfNeeded(currentItem: movie)
                    }
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

/// Afiş hücresi.
private struct MoviePosterCell: View {

    let movie: Movie
    let isFavorite: Bool
    let onTap: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                GridPosterView(url: movie.posterURL)
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
                        RatingBadge(rating: movie.rating)
                            .padding(Theme.Spacing.xs)
                    }

                Text(movie.title)
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
        // Afiş, kalp ve puan ayrı ayrı okunursa ızgarada gezinmek işkence
        // olur; hücre tek öğe, favori ise özel eylem.
        .accessibilityElement(children: .combine)
        .accessibilityAction(
            named: isFavorite ? "Favorilerden çıkar" : "Favorilere ekle",
            onToggleFavorite
        )
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

/// Film ve dizi ekranlarında ortak kategori şeridi.
struct MediaCategoryStrip: View {

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
