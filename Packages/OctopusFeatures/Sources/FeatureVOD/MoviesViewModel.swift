import Foundation
import Combine
import OctopusDomain
import OctopusDesignSystem

/// Film kataloğu: kategori, sayfalı liste, arama, favoriler.
@MainActor
public final class MoviesViewModel: ObservableObject {

    @Published public private(set) var categories: [MediaCategory] = []
    @Published public private(set) var movies: [Movie] = []
    @Published public private(set) var favoriteKeys: Set<String> = []
    @Published public private(set) var state: LoadableState<Int> = .idle

    @Published public private(set) var selectedCategoryID: MediaCategory.ID?
    @Published public var searchText = "" {
        didSet { scheduleSearch() }
    }

    public private(set) var isSearching = false
    /// Listenin sonuna gelindiğinde daha fazla yüklenebilir mi?
    public private(set) var canLoadMore = true

    private let dependencies: VODDependencies
    private let pageSize: Int
    private let searchDebounce: Duration

    private var activePlaylistID: Playlist.ID?
    private var isLoadingPage = false
    private var searchTask: Task<Void, Never>?
    private var favoritesTask: Task<Void, Never>?

    public init(
        dependencies: VODDependencies,
        // Referans projede tüm katalog tek seferde belleğe alınıyordu ve
        // 20.000 filmlik hesapta uygulama düşüyordu. Sayfa sayfa yüklenir.
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
        if movies.isEmpty { state = .loading }

        do {
            guard let playlist = try await dependencies.playlists.activePlaylist() else {
                state = .loaded(0)
                movies = []
                categories = []
                return
            }
            activePlaylistID = playlist.id
            categories = try await dependencies.vod.categories(playlistID: playlist.id)
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
            let page = try await dependencies.vod.movies(
                playlistID: playlistID,
                categoryID: selectedCategoryID,
                limit: pageSize,
                offset: 0
            )
            movies = page
            canLoadMore = page.count == pageSize
            state = .loaded(page.count)
        } catch {
            state = .failed(AppError.wrap(error))
        }
    }

    /// Kullanıcı listenin sonuna yaklaştığında çağrılır.
    public func loadMoreIfNeeded(currentItem movie: Movie) async {
        // Son öğeye gelinmeden birkaç satır önce tetiklenir ki kaydırma
        // duraklamasın.
        guard let index = movies.firstIndex(where: { $0.id == movie.id }),
              index >= movies.count - 8
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
            let page = try await dependencies.vod.movies(
                playlistID: playlistID,
                categoryID: selectedCategoryID,
                limit: pageSize,
                offset: movies.count
            )
            // Sıralama sabit olduğu için sayfalar üst üste binmez.
            movies.append(contentsOf: page)
            canLoadMore = page.count == pageSize
            state = .loaded(movies.count)
        } catch {
            // Sayfa hatası mevcut listeyi düşürmemeli.
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
            let results = try await dependencies.vod.search(
                query: query,
                playlistID: playlistID,
                limit: 200
            )
            guard !Task.isCancelled else { return }
            movies = results
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

    public func toggleFavorite(_ movie: Movie) async {
        _ = try? await dependencies.favorites.toggle(.movie(movie.id))
    }

    public func isFavorite(_ movie: Movie) -> Bool {
        favoriteKeys.contains(PlaybackItem.Source.movie(movie.id).storageKey)
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

    // MARK: - İzleme ilerlemesi

    /// Afiş üzerinde gösterilecek "kaldığın yer" oranı.
    public func progressFraction(for movie: Movie) async -> Double? {
        guard let stored = try? await dependencies.progress.progress(for: .movie(movie.id)),
              !stored.isFinished, stored.fraction > 0.01
        else { return nil }
        return stored.fraction
    }
}
