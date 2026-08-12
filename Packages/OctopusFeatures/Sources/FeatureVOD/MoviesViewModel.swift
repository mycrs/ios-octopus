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
    @Published public private(set) var isChangingCategory = false
    /// Listenin sonuna gelindiğinde daha fazla yüklenebilir mi?
    public private(set) var canLoadMore = true

    private let dependencies: VODDependencies
    private let pageSize: Int
    private let searchDebounce: Duration

    private var activePlaylistID: Playlist.ID?
    private var parentalFilter = ParentalFilter.open
    /// Depodan **çekilen** satır sayısı — `movies.count` değil.
    ///
    /// ⚠️ Süzme sonrası liste kısalıyor; ofset olarak `movies.count`
    /// kullanılsaydı gizlenen her film bir sonraki sayfayı geri kaydırır,
    /// aynı filmler tekrar tekrar gelirdi.
    private var fetchedRowCount = 0
    private var isLoadingPage = false
    private var catalogGeneration = 0
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
            parentalFilter = await .current(dependencies.parental)
            let allCategories = try await dependencies.vod.categories(playlistID: playlist.id)
            categories = parentalFilter.filter(allCategories)
            dropSelectionIfHidden()
            observeFavorites()
            await reloadFirstPage()
        } catch {
            state = .failed(AppError.wrap(error))
        }
    }

    public func selectCategory(_ id: MediaCategory.ID?) async {
        guard selectedCategoryID != id else { return }
        Haptics.selection()
        selectedCategoryID = id
        searchTask?.cancel()
        isSearching = false
        if !searchText.isEmpty { searchText = "" }
        isChangingCategory = true
        await reloadFirstPage()
    }

    private func reloadFirstPage() async {
        guard let playlistID = activePlaylistID else { return }

        catalogGeneration &+= 1
        let generation = catalogGeneration
        let categoryID = selectedCategoryID
        isLoadingPage = true
        defer {
            if generation == catalogGeneration {
                isLoadingPage = false
                isChangingCategory = false
            }
        }

        do {
            let batch = try await fetchVisiblePages(
                playlistID: playlistID,
                categoryID: categoryID,
                offset: 0
            )
            guard generation == catalogGeneration else { return }
            movies = batch.items
            fetchedRowCount = batch.fetchedCount
            canLoadMore = batch.canLoadMore
            state = .loaded(movies.count)
        } catch {
            guard generation == catalogGeneration else { return }
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

        let generation = catalogGeneration
        let categoryID = selectedCategoryID
        let offset = fetchedRowCount
        isLoadingPage = true
        defer {
            if generation == catalogGeneration { isLoadingPage = false }
        }

        do {
            let batch = try await fetchVisiblePages(
                playlistID: playlistID,
                categoryID: categoryID,
                offset: offset
            )
            guard generation == catalogGeneration,
                  categoryID == selectedCategoryID,
                  !isSearching
            else { return }
            movies.append(contentsOf: batch.items)
            fetchedRowCount += batch.fetchedCount
            canLoadMore = batch.canLoadMore
            state = .loaded(movies.count)
        } catch {
            // Sayfa hatası mevcut listeyi düşürmemeli.
            guard generation == catalogGeneration else { return }
            canLoadMore = false
        }
    }

    /// Listeye görünür en az bir film eklenene kadar sayfa çeker.
    ///
    /// Ebeveyn kilidi açıkken bir kategorinin tamamı yetişkin içerik
    /// olabilir. Tek sayfa çekip durmak listeyi boş gösterir, kullanıcı da
    /// "daha fazla" tetikleyecek bir şey göremediği için orada kalırdı.
    /// Üst sınır var: baştan sona gizli bir katalogda sonsuza kadar dönmesin.
    private struct PageBatch {
        var items: [Movie] = []
        var fetchedCount = 0
        var canLoadMore = true
    }

    private func fetchVisiblePages(
        playlistID: Playlist.ID,
        categoryID: MediaCategory.ID?,
        offset: Int
    ) async throws -> PageBatch {
        var batch = PageBatch()
        for _ in 0..<Self.maxPagesPerFetch {
            let page = try await dependencies.vod.movies(
                playlistID: playlistID,
                categoryID: categoryID,
                limit: pageSize,
                offset: offset + batch.fetchedCount
            )
            batch.fetchedCount += page.count
            batch.canLoadMore = page.count == pageSize

            // Sıralama sabit olduğu için sayfalar üst üste binmez.
            let allowed = parentalFilter.filter(page)
            batch.items.append(contentsOf: allowed)

            if !allowed.isEmpty || !batch.canLoadMore { return batch }
        }
        return batch
    }

    private static let maxPagesPerFetch = 5

    /// Seçili kategori az önce gizlendiyse "Tümü"ne dön.
    ///
    /// Kullanıcı yetişkin bir kategoride dururken kilidi kurmuş olabilir;
    /// seçim orada kalırsa katalog kalıcı olarak boş görünür.
    private func dropSelectionIfHidden() {
        guard let selected = selectedCategoryID else { return }
        if !categories.contains(where: { $0.id == selected }) {
            selectedCategoryID = nil
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
        catalogGeneration &+= 1
        let generation = catalogGeneration
        isSearching = true
        isChangingCategory = false

        do {
            let results = try await dependencies.vod.search(
                query: query,
                playlistID: playlistID,
                limit: 200
            )
            guard !Task.isCancelled, generation == catalogGeneration else { return }
            // Arama sonuçları da süzülür; aksi halde kilit aramayla atlatılırdı.
            movies = parentalFilter.filter(results)
            canLoadMore = false
            state = .loaded(movies.count)
        } catch {
            guard generation == catalogGeneration, !Task.isCancelled else { return }
            state = .failed(AppError.wrap(error))
        }
    }

    public func clearSearch() {
        searchTask?.cancel()
        let shouldReload = isSearching
        isSearching = false
        searchText = ""
        if shouldReload { Task { await reloadFirstPage() } }
    }

    // MARK: - Favoriler

    public func toggleFavorite(_ movie: Movie) async {
        guard let added = try? await dependencies.favorites.toggle(.movie(movie.id)) else {
            return
        }
        if added { Haptics.success() } else { Haptics.light() }
    }

    public func isFavorite(_ movie: Movie) -> Bool {
        favoriteKeys.contains(FavoriteTarget.movie(movie.id).storageKey)
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
