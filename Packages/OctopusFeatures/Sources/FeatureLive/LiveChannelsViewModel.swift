import Foundation
import Combine
import OctopusDomain
import OctopusDesignSystem

/// Canlı TV listesi: kategoriler, kanallar, arama ve favoriler.
@MainActor
public final class LiveChannelsViewModel: ObservableObject {

    @Published public private(set) var categories: [MediaCategory] = []
    @Published public private(set) var channels: [Channel] = []
    @Published public private(set) var favoriteKeys: Set<String> = []
    @Published public private(set) var state: LoadableState<Int> = .idle

    /// `nil` = tüm kanallar.
    @Published public private(set) var selectedCategoryID: MediaCategory.ID?
    @Published public var searchText = "" {
        didSet { scheduleSearch() }
    }

    /// Arama sonuçları listeyi geçici olarak değiştirir; temizlenince
    /// kullanıcı kaldığı kategoriye döner.
    public private(set) var isSearching = false

    private let dependencies: LiveDependencies
    private let searchDebounce: Duration

    private var activePlaylistID: Playlist.ID?
    private var searchTask: Task<Void, Never>?
    private var observationTask: Task<Void, Never>?
    private var favoritesTask: Task<Void, Never>?

    public init(
        dependencies: LiveDependencies,
        // Kullanıcı yazarken her tuşta sorgu atmak büyük kataloglarda
        // arayüzü kilitliyor. Referans projede bu değer 600 ms'e çekilmişti.
        searchDebounce: Duration = .milliseconds(300)
    ) {
        self.dependencies = dependencies
        self.searchDebounce = searchDebounce
    }

    deinit {
        searchTask?.cancel()
        observationTask?.cancel()
        favoritesTask?.cancel()
    }

    // MARK: - Yükleme

    public func load() async {
        if channels.isEmpty { state = .loading }

        do {
            guard let playlist = try await dependencies.playlists.activePlaylist() else {
                // Kaynak yoksa boş liste doğru davranış; hata değil.
                state = .loaded(0)
                channels = []
                categories = []
                return
            }
            activePlaylistID = playlist.id

            categories = try await dependencies.channels.categories(playlistID: playlist.id)
            observeChannels(playlistID: playlist.id, categoryID: selectedCategoryID)
            observeFavorites()
        } catch {
            state = .failed(AppError.wrap(error))
        }
    }

    /// Kategori değişimi.
    ///
    /// ⚠️ Liste dolu iken `.loading` durumuna geçilmiyor: referans projede
    /// bu, her kategori geçişinde spinner parlamasına ve kaydırma konumunun
    /// sıfırlanmasına yol açmıştı.
    public func selectCategory(_ id: MediaCategory.ID?) {
        guard selectedCategoryID != id else { return }
        selectedCategoryID = id
        clearSearch()

        guard let playlistID = activePlaylistID else { return }
        observeChannels(playlistID: playlistID, categoryID: id)
    }

    // MARK: - Arama

    private func scheduleSearch() {
        searchTask?.cancel()

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            // Arama temizlendi: kullanıcı kaldığı kategoriye dönmeli.
            if isSearching {
                isSearching = false
                if let playlistID = activePlaylistID {
                    observeChannels(playlistID: playlistID, categoryID: selectedCategoryID)
                }
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

        // Arama sonuçları canlı gözlemin üzerine yazar; gözlem durdurulur
        // ki senkronizasyon sonuçları arama listesini ezmesin.
        observationTask?.cancel()
        isSearching = true

        do {
            let results = try await dependencies.channels.search(
                query: query,
                playlistID: playlistID,
                limit: 200
            )
            guard !Task.isCancelled else { return }
            channels = results
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

    public func toggleFavorite(_ channel: Channel) async {
        do {
            _ = try await dependencies.favorites.toggle(.liveChannel(channel.id))
        } catch {
            state = .failed(AppError.wrap(error))
        }
    }

    public func isFavorite(_ channel: Channel) -> Bool {
        favoriteKeys.contains(PlaybackItem.Source.liveChannel(channel.id).storageKey)
    }

    // MARK: - Gözlem
    //
    // Senkronizasyon veritabanına yazdıkça liste kendini tazeler;
    // kullanıcı "yenile" demek zorunda kalmaz.

    private func observeChannels(playlistID: Playlist.ID, categoryID: MediaCategory.ID?) {
        observationTask?.cancel()
        observationTask = Task { [weak self, dependencies] in
            for await updated in dependencies.channels.observeChannels(
                playlistID: playlistID,
                categoryID: categoryID
            ) {
                guard let self, !Task.isCancelled else { return }
                // Arama sürerken gelen güncelleme sonuçları ezmemeli.
                guard !self.isSearching else { continue }
                self.channels = updated
                self.state = .loaded(updated.count)
            }
        }
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
