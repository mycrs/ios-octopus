import Foundation
import Combine
import OctopusDomain
import OctopusDesignSystem

/// Ana sayfa rafları: izlemeye devam et, son eklenenler, son izlenen kanallar.
@MainActor
public final class HomeViewModel: ObservableObject {

    /// "İzlemeye devam et" rafındaki tek öğe.
    ///
    /// Film ve bölüm aynı rafta gösterildiği için ortak bir sunum tipi
    /// kullanılır; ekran hangi tür olduğunu bilmek zorunda kalmaz.
    public struct ResumeItem: Identifiable, Equatable {
        public let id: String
        public let title: String
        public let subtitle: String?
        public let posterURL: URL?
        public let fraction: Double
        public let source: PlaybackItem.Source
    }

    @Published public private(set) var resumeItems: [ResumeItem] = []
    @Published public private(set) var recentlyAdded: [Movie] = []
    /// Son eklenen diziler — filmlerin altındaki raf.
    @Published public private(set) var recentSeries: [Series] = []

    /// Hero'daki hesap satırı: kullanıcı adı ve aboneliğe kalan gün.
    ///
    /// Referans uygulamada bu bilgi kocaman bir mor kartın içinde iki
    /// kutuya bölünmüştü. Burada tek satır: iOS'ta ikincil bilgi sessiz
    /// durur, yalnızca **acil olduğunda** (abonelik bitmek üzere) renk alır.
    @Published public private(set) var account: HomeAccount?
    @Published public private(set) var recentChannels: [Channel] = []
    @Published public private(set) var catalogMovies: [Movie] = []
    @Published public private(set) var catalogSeries: [Series] = []
    @Published public private(set) var catalogChannels: [Channel] = []
    @Published public private(set) var state: LoadableState<Int> = .idle
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var quickActionMessage: String?
    @Published public private(set) var quickActionFailed = false

    public var isEmpty: Bool {
        resumeItems.isEmpty && recentlyAdded.isEmpty
            && recentSeries.isEmpty && recentChannels.isEmpty
            && catalogMovies.isEmpty && catalogSeries.isEmpty && catalogChannels.isEmpty
    }

    public var displayedMovies: [Movie] { recentlyAdded.isEmpty ? catalogMovies : recentlyAdded }
    public var displayedSeries: [Series] { recentSeries.isEmpty ? catalogSeries : recentSeries }
    public var displayedChannels: [Channel] { recentChannels.isEmpty ? catalogChannels : recentChannels }
    public var movieShelfTitle: String { recentlyAdded.isEmpty ? "Filmler" : "Son eklenen filmler" }
    public var seriesShelfTitle: String { recentSeries.isEmpty ? "Diziler" : "Son eklenen diziler" }
    public var channelShelfTitle: String { recentChannels.isEmpty ? "Canlı TV" : "Son izlenen kanallar" }

    public var canRefresh: Bool {
        account != nil && !isRefreshing
    }


    private let dependencies: HomeDependencies
    private let shelfLimit: Int
    private let now: () -> Date
    private var loadGeneration = 0

    public init(
        dependencies: HomeDependencies,
        shelfLimit: Int = 12,
        now: @escaping () -> Date = Date.init
    ) {
        self.dependencies = dependencies
        self.shelfLimit = shelfLimit
        self.now = now
    }

    /// Saate göre karşılama — Android sürümüyle aynı davranış.
    public var greeting: String {
        switch Calendar.current.component(.hour, from: now()) {
        case 5..<12: return "Günaydın"
        case 12..<18: return "İyi günler"
        case 18..<22: return "İyi akşamlar"
        default: return "İyi geceler"
        }
    }


    public func load() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        if isEmpty { state = .loading }

        do {
            let activePlaylist = try await dependencies.playlists.activePlaylist()
            guard generation == loadGeneration, !Task.isCancelled else { return }
            guard let playlist = activePlaylist else {
                state = .loaded(0)
                clear()
                return
            }

            // Raflar süzülmeden önce kilit durumu bilinmeli.
            let filter = await ParentalFilter.current(dependencies.parental)
            guard generation == loadGeneration, !Task.isCancelled else { return }

            // Raflar birbirinden bağımsız; paralel yüklenir.
            async let resume = loadResumeItems(playlistID: playlist.id, filter: filter)
            async let added = dependencies.vod.recentlyAdded(
                playlistID: playlist.id,
                limit: shelfLimit
            )
            async let series = dependencies.series.recentlyAdded(
                playlistID: playlist.id,
                limit: shelfLimit
            )
            async let channels = dependencies.history.recentChannels(
                playlistID: playlist.id,
                limit: shelfLimit
            )

            let loadedResume = await resume
            let loadedMovies = filter.filter((try? await added) ?? [])
            let loadedSeries = filter.filter((try? await series) ?? [])
            let loadedChannels = filter.filter((try? await channels) ?? [])
            guard generation == loadGeneration, !Task.isCancelled else { return }

            // Tarihi olmayan içerik "son eklenen" değildir, ama katalog yine doludur.
            async let fallbackMovies = loadCatalogMovies(playlistID: playlist.id, filter: filter,
                                                        needed: loadedMovies.isEmpty, generation: generation)
            async let fallbackSeries = loadCatalogSeries(playlistID: playlist.id, filter: filter,
                                                        needed: loadedSeries.isEmpty, generation: generation)
            let movies = await fallbackMovies
            let collections = await fallbackSeries
            guard generation == loadGeneration, !Task.isCancelled else { return }

            // Kanal kataloğunu yalnızca diğer raflar boşsa, sınırlı sayfalarla oku.
            // İlk M3U açılışında geçmişin boş olması katalog yok demek değildir.
            var liveCatalog: [Channel] = []
            if loadedResume.isEmpty, loadedMovies.isEmpty, loadedSeries.isEmpty,
               loadedChannels.isEmpty, movies.isEmpty, collections.isEmpty {
                liveCatalog = await loadVisibleCatalog(generation: generation, allows: filter.allows(channel:)) {
                    limit, offset in
                    try await self.dependencies.channels.channels(
                        playlistID: playlist.id, categoryID: nil, limit: limit, offset: offset
                    )
                }
            }
            let currentID = try await dependencies.playlists.activePlaylist()?.id
            guard generation == loadGeneration, !Task.isCancelled, currentID == playlist.id else { return }

            account = HomeAccount(playlist: playlist, now: now())
            resumeItems = loadedResume
            recentlyAdded = loadedMovies
            recentSeries = loadedSeries
            recentChannels = loadedChannels
            catalogMovies = movies
            catalogSeries = collections
            catalogChannels = liveCatalog

            state = .loaded(
                resumeItems.count + recentlyAdded.count
                    + recentSeries.count + recentChannels.count
                    + catalogMovies.count + catalogSeries.count + catalogChannels.count
            )
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration, !Task.isCancelled else { return }
            state = .failed(AppError.wrap(error))
        }
    }

    private func loadCatalogMovies(playlistID: Playlist.ID, filter: ParentalFilter,
                                  needed: Bool, generation: Int) async -> [Movie] {
        guard needed, !Task.isCancelled else { return [] }
        return await loadVisibleCatalog(generation: generation, allows: filter.allows(movie:)) { limit, offset in
            try await self.dependencies.vod.movies(
                playlistID: playlistID, categoryID: nil, limit: limit, offset: offset
            )
        }
    }

    private func loadCatalogSeries(playlistID: Playlist.ID, filter: ParentalFilter,
                                  needed: Bool, generation: Int) async -> [Series] {
        guard needed, !Task.isCancelled else { return [] }
        return await loadVisibleCatalog(generation: generation, allows: filter.allows(series:)) { limit, offset in
            try await self.dependencies.series.series(
                playlistID: playlistID, categoryID: nil, limit: limit, offset: offset
            )
        }
    }

    private func loadVisibleCatalog<Item: Sendable>(
        generation: Int,
        allows: (Item) -> Bool,
        read: (Int, Int) async throws -> [Item]
    ) async -> [Item] {
        guard shelfLimit > 0 else { return [] }
        let pageSize = max(shelfLimit, 48)
        var offset = 0
        var visible: [Item] = []
        while visible.count < shelfLimit {
            guard generation == loadGeneration, !Task.isCancelled else { return [] }
            guard let page = try? await read(pageSize, offset) else { break }
            visible.append(contentsOf: page.filter(allows).prefix(shelfLimit - visible.count))
            guard page.count == pageSize else { break }
            offset += pageSize
        }
        return visible
    }

    /// Ana sayfadaki hızlı işlem: aktif listeyi yeniden eşitler ve rafları
    /// aynı ekranda günceller. Arka arkaya dokunmalar ikinci işi başlatmaz.
    public func refreshActivePlaylist() async {
        guard !isRefreshing else { return }

        guard let playlist = try? await dependencies.playlists.activePlaylist() else {
            quickActionFailed = true
            quickActionMessage = "Önce bir liste eklemelisin."
            return
        }

        isRefreshing = true
        quickActionMessage = nil
        defer { isRefreshing = false }

        do {
            try await dependencies.sync.sync(playlistID: playlist.id)
            await load()
            quickActionFailed = false
            quickActionMessage = "Liste yenilendi."
            Haptics.success()
        } catch {
            quickActionFailed = true
            quickActionMessage = AppError.wrap(error).userMessage
            Haptics.warning()
        }
    }

    /// İlerleme kayıtlarını gerçek içeriğe bağlar.
    ///
    /// Kayıtlar yalnızca anahtar taşır; başlık ve afiş için katalog
    /// depolarına sorulur. Silinmiş içeriğin kaydı sessizce atlanır —
    /// kullanıcı artık var olmayan bir filme tıklayamamalı.
    private func loadResumeItems(playlistID: Playlist.ID, filter: ParentalFilter) async -> [ResumeItem] {
        guard let stored = try? await dependencies.progress.continueWatching(
            playlistID: playlistID,
            limit: shelfLimit
        ) else { return [] }

        var items: [ResumeItem] = []

        for progress in stored {
            guard let source = PlaybackItem.Source(storageKey: progress.itemKey) else { continue }

            switch source {
            case .movie(let id):
                guard let movie = try? await dependencies.vod.movie(id: id),
                      filter.allows(movie: movie)
                else { continue }
                items.append(
                    ResumeItem(
                        id: progress.itemKey,
                        title: movie.title,
                        subtitle: nil,
                        posterURL: movie.posterURL,
                        fraction: progress.fraction,
                        source: source
                    )
                )

            case .episode(let id):
                guard let episode = try? await dependencies.series.episode(id: id) else { continue }
                let series = try? await dependencies.series.series(id: episode.seriesID)
                items.append(
                    ResumeItem(
                        id: progress.itemKey,
                        title: series?.title ?? episode.title,
                        subtitle: episode.shortLabel,
                        posterURL: series?.posterURL ?? episode.stillURL,
                        fraction: progress.fraction,
                        source: source
                    )
                )

            case .liveChannel:
                // Canlı yayında "kaldığın yer" kavramı yok.
                continue
            }
        }

        return items
    }

    private func clear() {
        account = nil
        resumeItems = []
        recentlyAdded = []
        recentSeries = []
        recentChannels = []
        catalogMovies = []
        catalogSeries = []
        catalogChannels = []
    }
}
