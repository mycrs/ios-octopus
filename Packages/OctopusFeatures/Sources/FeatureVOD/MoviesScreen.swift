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
    @Environment(\.brandColor) private var brandColor

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
            // Izgaranın iskeleti: kategori değiştirince ekran boşalıp
            // spinner'a düşmüyor, aynı düzen yerinde kalıyor.
            ScrollView { PosterGridSkeleton() }

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
                    action: viewModel.isSearching ? nil : { router.push(.about) }
                )
            } else {
                grid
            }
        }
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear.frame(height: 0).id(gridTopID)

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
                .opacity(viewModel.isChangingCategory ? 0.68 : 1)

                if viewModel.canLoadMore && !viewModel.isSearching {
                    ProgressView()
                        .tint(brandColor)
                        .padding(Theme.Spacing.lg)
                }
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .overlay(alignment: .top) {
                if viewModel.isChangingCategory {
                    CatalogTransitionOverlay()
                        .padding(.top, Theme.Spacing.md)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .onChange(of: viewModel.selectedCategoryID) { _ in
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo(gridTopID, anchor: .top)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: viewModel.isChangingCategory)
        }
        .padding(.bottom, 56)
    }

    private var gridTopID: String { "movies-grid-top" }
}
