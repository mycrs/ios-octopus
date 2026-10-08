import Foundation
import Combine
import OctopusDomain
import OctopusDesignSystem

/// Birleşik arama: kanal, film ve dizi tek ekranda.
@MainActor
public final class SearchViewModel: ObservableObject {

    @Published public var searchText = "" {
        didSet { scheduleSearch() }
    }

    @Published public private(set) var channels: [Channel] = []
    @Published public private(set) var movies: [Movie] = []
    @Published public private(set) var series: [Series] = []
    @Published public private(set) var state: LoadableState<Int> = .idle

    /// Kullanıcı henüz bir şey yazmadı.
    public var hasQuery: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var isEmpty: Bool {
        channels.isEmpty && movies.isEmpty && series.isEmpty
    }

    private let dependencies: SearchDependencies
    private let debounce: Duration
    private let resultLimit: Int

    private var activePlaylistID: Playlist.ID?
    private var parentalFilter = ParentalFilter.open
    private var searchTask: Task<Void, Never>?
    private var contextGeneration = 0
    private var searchGeneration = 0
    private var isPreparing = false

    public init(
        dependencies: SearchDependencies,
        debounce: Duration = .milliseconds(300),
        // Her tür için ayrı sınır: tek tür sonuçları ekranı doldurmasın.
        resultLimit: Int = 30
    ) {
        self.dependencies = dependencies
        self.debounce = debounce
        self.resultLimit = resultLimit
    }

    deinit {
        searchTask?.cancel()
    }

    public func prepare() async {
        contextGeneration &+= 1
        let context = contextGeneration
        isPreparing = true
        searchTask?.cancel()
        searchGeneration &+= 1
        activePlaylistID = nil
        clear()
        state = .idle

        let playlistID = try? await dependencies.playlists.activePlaylist()?.id
        let filter = await ParentalFilter.current(dependencies.parental)
        guard context == contextGeneration, !Task.isCancelled else { return }
        activePlaylistID = playlistID
        parentalFilter = filter
        isPreparing = false
        // Kaynak veya erişim değişince ekrandaki sorgu yeni bağlamda çalışır.
        scheduleSearch()
    }

    // MARK: - Arama

    private func scheduleSearch() {
        searchTask?.cancel()
        searchGeneration &+= 1
        let generation = searchGeneration

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2, !isPreparing else {
            clear()
            state = .idle
            return
        }

        searchTask = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard let self, !Task.isCancelled else { return }
            await self.performSearch(query, generation: generation)
        }
    }

    private func performSearch(_ query: String, generation: Int) async {
        guard generation == searchGeneration, !Task.isCancelled else { return }
        guard let playlistID = activePlaylistID else {
            clear()
            state = .loaded(0)
            return
        }

        state = .loading

        // Üç arama paralel: hiçbiri diğerini beklemesin.
        async let channelResults = dependencies.channels.search(
            query: query, playlistID: playlistID, limit: resultLimit
        )
        async let movieResults = dependencies.vod.search(
            query: query, playlistID: playlistID, limit: resultLimit
        )
        async let seriesResults = dependencies.series.search(
            query: query, playlistID: playlistID, limit: resultLimit
        )

        // Bir tür başarısız olursa (o paket hesapta yoksa) diğerleri gösterilir.
        let foundChannels = (try? await channelResults) ?? []
        let foundMovies = (try? await movieResults) ?? []
        let foundSeries = (try? await seriesResults) ?? []

        guard !Task.isCancelled, generation == searchGeneration,
              playlistID == activePlaylistID else { return }

        // ⚠️ Süzme burada şart: arama, kilidi atlatmanın en kolay yoludur —
        // yetişkin içerik listede gizliyken adıyla aratılabilirdi.
        channels = parentalFilter.filter(foundChannels)
        movies = parentalFilter.filter(foundMovies)
        series = parentalFilter.filter(foundSeries)

        state = .loaded(channels.count + movies.count + series.count)
    }

    public func clearSearch() {
        searchTask?.cancel()
        searchText = ""
        clear()
        state = .idle
    }

    private func clear() {
        channels = []
        movies = []
        series = []
    }
}
