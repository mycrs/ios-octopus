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
    @Published public private(set) var isChangingCategory = false
    public private(set) var canLoadMore = true

    private let dependencies: SeriesDependencies
    private let pageSize: Int
    private let searchDebounce: Duration

    private var activePlaylistID: Playlist.ID?
    private var parentalFilter = ParentalFilter.open
    /// Depodan **çekilen** satır sayısı — `series.count` değil.
    private var fetchedRowCount = 0
    private var isLoadingPage = false
    private var catalogGeneration = 0
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
            parentalFilter = await .current(dependencies.parental)
            let allCategories = try await dependencies.series.categories(playlistID: playlist.id)
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
            series = batch.items
            fetchedRowCount = batch.fetchedCount
            canLoadMore = batch.canLoadMore
            state = .loaded(series.count)
        } catch {
            guard generation == catalogGeneration else { return }
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
            series.append(contentsOf: batch.items)
            fetchedRowCount += batch.fetchedCount
            canLoadMore = batch.canLoadMore
            state = .loaded(series.count)
        } catch {
            guard generation == catalogGeneration else { return }
            canLoadMore = false
        }
    }

    /// Listeye görünür en az bir dizi eklenene kadar sayfa çeker.
    ///
    /// Kalıp film ekranıyla aynı — gerekçesi de: ofset **çekilen ham satır**
    /// sayısıdır, görünen değil. Ebeveyn kilidi bir sayfanın tamamını
    /// gizleyebilir; tek sayfa çekip durmak listeyi boş bırakırdı.
    private struct PageBatch {
        var items: [Series] = []
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
            let page = try await dependencies.series.series(
                playlistID: playlistID,
                categoryID: categoryID,
                limit: pageSize,
                offset: offset + batch.fetchedCount
            )
            batch.fetchedCount += page.count
            batch.canLoadMore = page.count == pageSize

            let allowed = parentalFilter.filter(page)
            batch.items.append(contentsOf: allowed)

            if !allowed.isEmpty || !batch.canLoadMore { return batch }
        }
        return batch
    }

    private static let maxPagesPerFetch = 5

    /// Seçili kategori az önce gizlendiyse "Tümü"ne dön.
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
            let results = try await dependencies.series.search(
                query: query,
                playlistID: playlistID,
                limit: 200
            )
            guard !Task.isCancelled, generation == catalogGeneration else { return }
            // Arama sonuçları da süzülür; aksi halde kilit aramayla atlatılırdı.
            series = parentalFilter.filter(results)
            canLoadMore = false
            state = .loaded(series.count)
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

    public func toggleFavorite(_ item: Series) async {
        guard let added = try? await dependencies.favorites.toggle(.series(item.id)) else {
            return
        }
        if added { Haptics.success() } else { Haptics.light() }
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
