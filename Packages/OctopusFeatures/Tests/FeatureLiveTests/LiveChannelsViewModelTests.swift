import XCTest
import OctopusDomain
@testable import FeatureLive

/// Canlı TV listesi: yükleme, kategori geçişi, arama, favoriler.
@MainActor
final class LiveChannelsViewModelTests: XCTestCase {

    private var playlists: StubPlaylists!
    private var channels: StubChannels!
    private var favorites: StubFavorites!

    override func setUp() async throws {
        playlists = StubPlaylists()
        channels = StubChannels()
        favorites = StubFavorites()
    }

    private func makeViewModel() -> LiveChannelsViewModel {
        LiveChannelsViewModel(
            dependencies: LiveDependencies(
                playlists: playlists,
                channels: channels,
                epg: NoopEPG(),
                favorites: favorites
            ),
            // Testte beklememek için çok kısa gecikme.
            searchDebounce: .milliseconds(10)
        )
    }

    private func waitABit(_ milliseconds: UInt64 = 120) async {
        try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }

    // MARK: - Yükleme

    func test_load_withoutActivePlaylist_showsEmptyNotError() async {
        // Kaynak yoksa bu bir hata değil; kullanıcı henüz eklememiştir.
        playlists.active = nil

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertTrue(viewModel.channels.isEmpty)
        XCTAssertEqual(viewModel.state, .loaded(0))
    }

    func test_load_populatesCategoriesAndChannels() async {
        channels.categories = [makeCategory("spor", "Spor")]
        channels.stored = [makeChannel("1", "TRT 1"), makeChannel("2", "Show")]

        let viewModel = makeViewModel()
        await viewModel.load()
        await waitABit()

        XCTAssertEqual(viewModel.categories.map(\.name), ["Spor"])
        XCTAssertEqual(viewModel.channels.map(\.name), ["TRT 1", "Show"])
    }

    // MARK: - Kategori geçişi

    func test_selectCategory_filtersObservation() async {
        channels.categories = [makeCategory("spor", "Spor")]
        channels.stored = [makeChannel("1", "TRT 1")]

        let viewModel = makeViewModel()
        await viewModel.load()
        await waitABit()

        viewModel.selectCategory(MediaCategory.ID("spor"))
        await waitABit()

        XCTAssertEqual(viewModel.selectedCategoryID?.value, "spor")
        XCTAssertEqual(channels.observedCategoryIDs.last??.value, "spor")
    }

    func test_selectingSameCategoryTwiceDoesNotReobserve() async {
        let viewModel = makeViewModel()
        await viewModel.load()
        await waitABit()

        let countBefore = channels.observedCategoryIDs.count
        viewModel.selectCategory(nil)   // zaten nil
        XCTAssertEqual(channels.observedCategoryIDs.count, countBefore)
    }

    // MARK: - Arama

    func test_searchIsDebounced() async {
        channels.searchResults = [makeChannel("9", "Spor Kanalı")]

        let viewModel = makeViewModel()
        await viewModel.load()
        await waitABit()

        // Kullanıcı hızla yazıyor: her tuşta sorgu atılmamalı.
        viewModel.searchText = "s"
        viewModel.searchText = "sp"
        viewModel.searchText = "spo"
        await waitABit()

        XCTAssertEqual(channels.searchQueries, ["spo"], "Yalnızca son sorgu çalışmalı")
        XCTAssertEqual(viewModel.channels.map(\.name), ["Spor Kanalı"])
    }

    func test_clearingSearchRestoresCategoryList() async {
        channels.stored = [makeChannel("1", "TRT 1")]
        channels.searchResults = [makeChannel("9", "Spor Kanalı")]

        let viewModel = makeViewModel()
        await viewModel.load()
        await waitABit()

        viewModel.searchText = "spor"
        await waitABit()
        XCTAssertEqual(viewModel.channels.map(\.name), ["Spor Kanalı"])

        viewModel.searchText = ""
        await waitABit()

        XCTAssertFalse(viewModel.isSearching)
        XCTAssertEqual(viewModel.channels.map(\.name), ["TRT 1"], "Kategori listesine dönmeli")
    }

    func test_whitespaceOnlySearchIsIgnored() async {
        let viewModel = makeViewModel()
        await viewModel.load()
        await waitABit()

        viewModel.searchText = "   "
        await waitABit()

        XCTAssertTrue(channels.searchQueries.isEmpty)
    }

    // MARK: - Favoriler

    func test_toggleFavoriteUpdatesState() async {
        channels.stored = [makeChannel("1", "TRT 1")]

        let viewModel = makeViewModel()
        await viewModel.load()
        await waitABit()

        let channel = viewModel.channels[0]
        XCTAssertFalse(viewModel.isFavorite(channel))

        await viewModel.toggleFavorite(channel)
        await waitABit()

        XCTAssertTrue(viewModel.isFavorite(channel))
    }

    // MARK: - Canlı gözlem

    func test_syncWritesAppearWithoutManualRefresh() async {
        channels.stored = [makeChannel("1", "TRT 1")]

        let viewModel = makeViewModel()
        await viewModel.load()
        await waitABit()
        XCTAssertEqual(viewModel.channels.count, 1)

        // Senkronizasyon yeni kanal yazdı.
        channels.emit([makeChannel("1", "TRT 1"), makeChannel("2", "Yeni")])
        await waitABit()

        XCTAssertEqual(viewModel.channels.count, 2, "Gözlem ekranı tazelemeli")
    }

    // MARK: - Yardımcılar

    private func makeChannel(_ id: String, _ name: String) -> Channel {
        Channel(id: Channel.ID(id), playlistID: "p1", name: name, streamKey: id)
    }

    private func makeCategory(_ id: String, _ name: String) -> MediaCategory {
        MediaCategory(id: MediaCategory.ID(id), playlistID: "p1", kind: .live, name: name)
    }
}

// MARK: - Sahteler

private final class StubPlaylists: PlaylistRepository, @unchecked Sendable {
    var active: Playlist? = Playlist(
        id: "p1",
        name: "Kaynak",
        kind: .m3u(url: URL(string: "http://example.com/p.m3u")!),
        createdAt: Date(timeIntervalSince1970: 0),
        isActive: true
    )

    func all() async throws -> [Playlist] { active.map { [$0] } ?? [] }
    func playlist(id: Playlist.ID) async throws -> Playlist? { active }
    func activePlaylist() async throws -> Playlist? { active }
    func add(_ playlist: Playlist, password: String?) async throws {}
    func update(_ playlist: Playlist) async throws {}
    func setActive(id: Playlist.ID) async throws {}
    func delete(id: Playlist.ID) async throws {}
}

private final class StubChannels: ChannelRepository, @unchecked Sendable {

    var stored: [Channel] = []
    var categories: [MediaCategory] = []
    var searchResults: [Channel] = []

    private(set) var searchQueries: [String] = []
    private(set) var observedCategoryIDs: [MediaCategory.ID?] = []

    private var continuation: AsyncStream<[Channel]>.Continuation?

    func categories(playlistID: Playlist.ID) async throws -> [MediaCategory] { categories }

    func channels(
        playlistID: Playlist.ID,
        categoryID: MediaCategory.ID?
    ) async throws -> [Channel] { stored }

    func channel(id: Channel.ID) async throws -> Channel? {
        stored.first { $0.id == id }
    }

    func search(query: String, playlistID: Playlist.ID, limit: Int) async throws -> [Channel] {
        searchQueries.append(query)
        return searchResults
    }

    func observeChannels(
        playlistID: Playlist.ID,
        categoryID: MediaCategory.ID?
    ) -> AsyncStream<[Channel]> {
        observedCategoryIDs.append(categoryID)
        return AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(stored)
        }
    }

    /// Senkronizasyonun veritabanına yazmasını taklit eder.
    func emit(_ channels: [Channel]) {
        continuation?.yield(channels)
    }
}

private final class StubFavorites: FavoritesRepository, @unchecked Sendable {

    private var keys: Set<String> = []
    private var continuation: AsyncStream<Set<String>>.Continuation?

    func isFavorite(_ source: PlaybackItem.Source) async throws -> Bool {
        keys.contains(source.storageKey)
    }

    func toggle(_ source: PlaybackItem.Source) async throws -> Bool {
        let key = source.storageKey
        let added: Bool
        if keys.contains(key) {
            keys.remove(key)
            added = false
        } else {
            keys.insert(key)
            added = true
        }
        continuation?.yield(keys)
        return added
    }

    func favoriteChannels(playlistID: Playlist.ID) async throws -> [Channel] { [] }
    func favoriteMovies(playlistID: Playlist.ID) async throws -> [Movie] { [] }
    func favoriteSeries(playlistID: Playlist.ID) async throws -> [Series] { [] }

    func observeFavoriteKeys() -> AsyncStream<Set<String>> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(keys)
        }
    }
}

private struct NoopEPG: EPGRepository {
    func nowPlaying(epgChannelID: String, at date: Date) async throws -> EPGProgram? { nil }
    func nowPlaying(epgChannelIDs: [String], at date: Date) async throws -> [String: EPGProgram] { [:] }
    func programs(epgChannelID: String, from: Date, to: Date) async throws -> [EPGProgram] { [] }
    func purgePrograms(before date: Date) async throws {}
}
