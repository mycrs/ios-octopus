import Foundation
import Combine
import OctopusDomain
import OctopusDesignSystem

/// Dizi kataloğu: kategori, sayfalı liste, arama, favoriler.
///
/// ## Neden `MoviesViewModel` ile ortak bir taban yok?
/// İki katalog yüzeysel olarak benzer ama farklı depolara, farklı favori
/// anahtarlarına ve (Faz 8'de) farklı detay akışlarına bağlanıyor.
/// Ortak generic taban 8+ closure parametresi gerektirir; okunabilirlik
/// kazancı olmadan davranış riski doğurur. Referans projede de aynı
/// değerlendirme yapılıp bilinçli olarak pas geçilmiş.
@MainActor
public final class SeriesViewModel: ObservableObject {

    @Published public private(set) var categories: [MediaCategory] = []
    @Published public private(set) var series: [Series] = []
    @Published public private(set) var favoriteKeys: Set<String> = []
    @Published public private(set) var state: LoadableState<Int> = .idle

    @Published public private(set) var selectedCategoryID: MediaCategory.ID?
    @Published public var searchText = "" {
        didSet { scheduleSearch() }
    }

    public private(set) var isSearching = false
    public private(set) var canLoadMore = true

    private let dependencies: SeriesDependencies
    private let pageSize: Int
    private let searchDebounce: Duration

    private var activePlaylistID: Playlist.ID?
    private var isLoadingPage = false
    private var searchTask: Task<Void, Never>?
    private var favoritesTask: Task<Void, Never>?

    public init(
        dependencies: SeriesDependencies,
        pageSize: Int = 60,
        searchDebounce: Duration = .milliseconds(300)
    ) {
        self.dependencies = dependencies
        self.pageSize = pageSize
        self.searchDebounce = searchDebounce
    }

    deinit {
        searchTask?.cancel()
        favoritesTask?.cancel()
    }

    // MARK: - Yükleme

    public func load() async {
        if series.isEmpty { state = .loading }

        do {
            guard let playlist = try await dependencies.playlists.activePlaylist() else {
                state = .loaded(0)
                series = []
                categories = []
                return
            }
            activePlaylistID = playlist.id
            categories = try await dependencies.series.categories(playlistID: playlist.id)
            observeFavorites()
            await reloadFirstPage()
        } catch {
            state = .failed(AppError.wrap(error))
        }
    }

    public func selectCategory(_ id: MediaCategory.ID?) async {
        guard selectedCategoryID != id else { return }
        selectedCategoryID = id
        clearSearch()
        await reloadFirstPage()
    }

    private func reloadFirstPage() async {
        guard let playlistID = activePlaylistID else { return }

        canLoadMore = true
        isLoadingPage = true
        defer { isLoadingPage = false }

        do {
            let page = try await dependencies.series.series(
                playlistID: playlistID,
                categoryID: selectedCategoryID,
                limit: pageSize,
                offset: 0
            )
            series = page
            canLoadMore = page.count == pageSize
            state = .loaded(page.count)
        } catch {
            state = .failed(AppError.wrap(error))
        }
    }

    public func loadMoreIfNeeded(currentItem item: Series) async {
        guard let index = series.firstIndex(where: { $0.id == item.id }),
              index >= series.count - 8
        else { return }
        await loadMore()
    }

    public func loadMore() async {
        guard canLoadMore, !isLoadingPage, !isSearching,
              let playlistID = activePlaylistID
        else { return }

        isLoadingPage = true
        defer { isLoadingPage = false }

        do {
            let page = try await dependencies.series.series(
                playlistID: playlistID,
                categoryID: selectedCategoryID,
                limit: pageSize,
                offset: series.count
            )
            series.append(contentsOf: page)
            canLoadMore = page.count == pageSize
            state = .loaded(series.count)
        } catch {
            canLoadMore = false
        }
    }

    // MARK: - Arama

    private func scheduleSearch() {
        searchTask?.cancel()

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            if isSearching {
                isSearching = false
                Task { await reloadFirstPage() }
            }
            return
        }

        searchTask = Task { [weak self, searchDebounce] in
            try? await Task.sleep(for: searchDebounce)
            guard let self, !Task.isCancelled else { return }
            await self.performSearch(query)
        }
    }

    private func performSearch(_ query: String) async {
        guard let playlistID = activePlaylistID else { return }
        isSearching = true

        do {
            let results = try await dependencies.series.search(
                query: query,
                playlistID: playlistID,
                limit: 200
            )
            guard !Task.isCancelled else { return }
            series = results
            canLoadMore = false
            state = .loaded(results.count)
        } catch {
            state = .failed(AppError.wrap(error))
        }
    }

    public func clearSearch() {
        searchTask?.cancel()
        searchText = ""
        isSearching = false
    }

    // MARK: - Favoriler

    public func toggleFavorite(_ item: Series) async {
        _ = try? await dependencies.favorites.toggle(.series(item.id))
    }

    public func isFavorite(_ item: Series) -> Bool {
        favoriteKeys.contains(FavoriteTarget.series(item.id).storageKey)
    }

    private func observeFavorites() {
        favoritesTask?.cancel()
        favoritesTask = Task { [weak self, dependencies] in
            for await keys in dependencies.favorites.observeFavoriteKeys() {
                guard let self, !Task.isCancelled else { return }
                self.favoriteKeys = keys
            }
        }
    }
}
