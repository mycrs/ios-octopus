import XCTest
import OctopusDomain
@testable import FeatureLive

/// Canlı TV listesi: yükleme, kategori geçişi, arama, favoriler.
@MainActor
final class LiveChannelsViewModelTests: XCTestCase {

    private var playlists: StubPlaylists!
    private var channels: StubChannels!
    private var favorites: StubFavorites!
    private var epg: StubEPG!
    private var history: StubHistory!
    private var parental: StubParental!

    override func setUp() async throws {
        playlists = StubPlaylists()
        channels = StubChannels()
        favorites = StubFavorites()
        epg = StubEPG()
        history = StubHistory()
        parental = StubParental()
    }

    private func makeViewModel() -> LiveChannelsViewModel {
        LiveChannelsViewModel(
            dependencies: LiveDependencies(
                playlists: playlists,
                channels: channels,
                epg: epg,
                favorites: favorites,
                history: history,
                resolver: LiveTestPlayback.makeResolver(),
                streams: LiveStubStreams(),
                progress: LiveStubProgress(),
                parental: parental
            ),
            // Testte beklememek için çok kısa gecikmeler.
            searchDebounce: .milliseconds(10),
            epgRefreshInterval: .seconds(3600)
        )
    }

    private func waitABit(_ milliseconds: UInt64 = 120) async {
        try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }

    /// Koşul gerçekleşene kadar kısa aralıklarla yoklar.
    ///
    /// ⚠️ Sabit `sleep` ile beklemek CI'da rastgele kırmızıya yol açıyordu:
    /// koşucu paralel iş yüzünden yüklüyken geciktirme görevi verilen süre
    /// içinde sıraya girmiyor. Bekleme süresi değil **koşul** ölçülür.
    /// (Bir şeyin *olmadığını* doğrulayan testlerde hâlâ `waitABit` gerekir.)
    private func waitUntil(
        _ description: String,
        timeoutMS: UInt64 = 3_000,
        _ condition: () -> Bool
    ) async {
        let step: UInt64 = 10
        var waited: UInt64 = 0

        while waited < timeoutMS {
            if condition() { return }
            try? await Task.sleep(nanoseconds: step * 1_000_000)
            waited += step
        }
        XCTFail("Zaman aşımı: \(description)")
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
        await waitUntil("kanallar gelmeli") { viewModel.channels.count == 2 }

        XCTAssertEqual(viewModel.categories.map(\.name), ["Spor"])
        XCTAssertEqual(viewModel.channels.map(\.name), ["TRT 1", "Show"])
    }

    // MARK: - Kategori geçişi

    func test_selectCategory_filtersObservation() async {
        channels.categories = [makeCategory("spor", "Spor")]
        channels.stored = [makeChannel("1", "TRT 1")]

        let viewModel = makeViewModel()
        await viewModel.load()
        await waitUntil("ilk gözlem başlamalı") { channels.isObserving }

        viewModel.selectCategory(MediaCategory.ID("spor"))
        await waitUntil("kategori gözlemi yenilenmeli") {
            channels.observedCategoryIDs.last??.value == "spor"
        }

        XCTAssertEqual(viewModel.selectedCategoryID?.value, "spor")
    }

    func test_selectingSameCategoryTwiceDoesNotReobserve() async {
        let viewModel = makeViewModel()
        await viewModel.load()
        await waitUntil("gözlem başlamalı") { channels.isObserving }

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
        await waitUntil("arama sonucu listeye yansımalı") {
            viewModel.channels.map(\.name) == ["Spor Kanalı"]
        }

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
        await waitUntil("arama sonucu gelmeli") {
            viewModel.channels.map(\.name) == ["Spor Kanalı"]
        }

        viewModel.searchText = ""
        await waitUntil("kategori listesine dönmeli") {
            viewModel.channels.map(\.name) == ["TRT 1"]
        }

        XCTAssertFalse(viewModel.isSearching)
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
        await waitUntil("kanal listesi gelmeli") { !viewModel.channels.isEmpty }

        let channel = viewModel.channels[0]
        XCTAssertFalse(viewModel.isFavorite(channel))

        await viewModel.toggleFavorite(channel)
        await waitUntil("favori durumu yansımalı") { viewModel.isFavorite(channel) }
    }

    // MARK: - Yayın akışı

    func test_currentProgramIsMatchedByEPGChannelID() async {
        channels.stored = [
            makeChannel("1", "TRT 1", epgID: "trt1.tr"),
            makeChannel("2", "Eşleşmeyen", epgID: "yok.tr"),
            makeChannel("3", "Kimliksiz", epgID: nil)
        ]
        epg.programs = ["trt1.tr": makeProgram("Haberler")]

        let viewModel = makeViewModel()
        await viewModel.load()
        await waitUntil("kanallar ve rehber gelmeli") {
            viewModel.channels.count == 3 && !viewModel.nowPlaying.isEmpty
        }

        XCTAssertEqual(viewModel.currentProgram(for: viewModel.channels[0])?.title, "Haberler")
        XCTAssertNil(viewModel.currentProgram(for: viewModel.channels[1]))
        XCTAssertNil(
            viewModel.currentProgram(for: viewModel.channels[2]),
            "EPG kimliği olmayan kanal program göstermemeli"
        )
    }

    func test_missingGuideDoesNotBreakList() async {
        // Rehber hiç çekilmemişse kanal listesi yine çalışmalı.
        channels.stored = [makeChannel("1", "TRT 1", epgID: "trt1.tr")]
        epg.programs = [:]

        let viewModel = makeViewModel()
        await viewModel.load()
        await waitUntil("kanal gelmeli") { viewModel.channels.count == 1 }

        XCTAssertNil(viewModel.currentProgram(for: viewModel.channels[0]))
    }

    // MARK: - Ebeveyn kilidi

    func test_lockedParentalControlHidesAdultChannels() async {
        channels.stored = [
            makeChannel("1", "Normal"),
            makeAdultChannel("2", "Yetişkin")
        ]
        parental.enabled = true
        parental.unlocked = false

        let viewModel = makeViewModel()
        await viewModel.load()
        await waitUntil("süzülmüş liste gelmeli") {
            viewModel.channels.map(\.name) == ["Normal"]
        }
    }

    func test_unlockedParentalControlShowsEverything() async {
        channels.stored = [
            makeChannel("1", "Normal"),
            makeAdultChannel("2", "Yetişkin")
        ]
        parental.enabled = true
        parental.unlocked = true

        let viewModel = makeViewModel()
        await viewModel.load()
        await waitUntil("iki kanal da gelmeli") { viewModel.channels.count == 2 }
    }

    func test_searchAlsoRespectsParentalLock() async {
        // Kilit aramayla atlatılamamalı.
        channels.searchResults = [
            makeChannel("1", "Normal Sonuç"),
            makeAdultChannel("2", "Yetişkin Sonuç")
        ]
        parental.enabled = true
        parental.unlocked = false

        let viewModel = makeViewModel()
        await viewModel.load()
        await waitABit()

        viewModel.searchText = "sonuç"
        await waitUntil("arama sonucu süzülmüş gelmeli") {
            viewModel.channels.map(\.name) == ["Normal Sonuç"]
        }
    }

    // MARK: - Numarayla geçiş

    func test_numberQueryPutsMatchingChannelFirst() async {
        // "205" yazınca FTS adında 205 geçenleri buluyor; asıl istenen
        // 205 numaralı kanal ve o en üstte olmalı.
        channels.searchResults = [makeChannel("x", "Kanal 2050")]
        channels.byNumber = [205: makeChannel("hedef", "Hedef Kanal", number: 205)]

        let viewModel = makeViewModel()
        await viewModel.load()

        viewModel.searchText = "205"
        await waitUntil("numara eşleşmesi üstte olmalı") {
            viewModel.channels.first?.name == "Hedef Kanal"
        }

        XCTAssertEqual(viewModel.channels.map(\.name), ["Hedef Kanal", "Kanal 2050"])
        XCTAssertEqual(channels.numberLookups, [205])
    }

    func test_numberMatchIsNotDuplicated() async {
        // Aynı kanal hem ad aramasından hem numaradan gelirse iki kez çıkmamalı.
        let target = makeChannel("hedef", "Hedef", number: 7)
        channels.searchResults = [target]
        channels.byNumber = [7: target]

        let viewModel = makeViewModel()
        await viewModel.load()

        viewModel.searchText = "7"
        await waitUntil("sonuç gelmeli") { !viewModel.channels.isEmpty }

        XCTAssertEqual(viewModel.channels.count, 1)
    }

    func test_textQueryDoesNotTriggerNumberLookup() async {
        channels.searchResults = [makeChannel("1", "Spor")]

        let viewModel = makeViewModel()
        await viewModel.load()

        viewModel.searchText = "spor"
        await waitUntil("sonuç gelmeli") { !viewModel.channels.isEmpty }

        XCTAssertTrue(channels.numberLookups.isEmpty, "Metin sorgusunda numara aranmamalı")
    }

    func test_lockedAdultChannelIsNotReachableByNumber() async {
        // ⚠️ Numarayla geçiş, kilidi atlatmanın bir başka yolu olurdu.
        channels.searchResults = []
        channels.byNumber = [99: makeAdultChannel("gizli", "Yetişkin", number: 99)]
        parental.enabled = true
        parental.unlocked = false

        let viewModel = makeViewModel()
        await viewModel.load()

        viewModel.searchText = "99"
        await waitABit()

        XCTAssertTrue(viewModel.channels.isEmpty, "Kilitliyken numarayla da açılmamalı")
    }

    // MARK: - Kaldığın kanal önizlemesi

    func test_lastWatchedChannelIsLoaded() async {
        channels.stored = [makeChannel("1", "TRT 1")]
        history.channels = [makeChannel("1", "TRT 1")]

        let viewModel = makeViewModel()
        await viewModel.load()
        await waitUntil("son izlenen kanal yüklenmeli") {
            viewModel.lastWatchedChannel != nil
        }

        XCTAssertEqual(viewModel.lastWatchedChannel?.name, "TRT 1")
    }

    func test_noWatchHistoryMeansNoPreview() async {
        history.channels = []

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertNil(viewModel.lastWatchedChannel)
    }

    func test_lockedAdultChannelDoesNotAppearAsLastWatched() async {
        // ⚠️ Önizleme kartı da kilidi atlatmanın bir yolu olurdu.
        history.channels = [makeAdultChannel("gizli", "Yetişkin")]
        parental.enabled = true
        parental.unlocked = false

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertNil(viewModel.lastWatchedChannel)
    }

    // MARK: - Kalan süre metni

    private func program(startOffset: TimeInterval, endOffset: TimeInterval) -> EPGProgram {
        let now = Date(timeIntervalSince1970: 1_000_000)
        return EPGProgram(
            id: "p",
            epgChannelID: "c",
            title: "Program",
            startDate: now.addingTimeInterval(startOffset),
            endDate: now.addingTimeInterval(endOffset)
        )
    }

    private var referenceNow: Date { Date(timeIntervalSince1970: 1_000_000) }

    func test_remainingTextFormats() async {
        let cases: [(TimeInterval, String?)] = [
            (32 * 60, "32 dk"),
            (60 * 60, "1 sa"),
            (65 * 60, "1 sa 5 dk"),
            (120 * 60, "2 sa"),
            (30, nil),          // bir dakikanın altı gizlenir
            (-60, nil)          // bitmiş program
        ]

        for (seconds, expected) in cases {
            let item = program(startOffset: -3_600, endOffset: seconds)
            XCTAssertEqual(
                LiveChannelsViewModel.remainingText(item, at: referenceNow),
                expected,
                "\(seconds) saniye"
            )
        }
    }

    // MARK: - Canlı gözlem

    func test_syncWritesAppearWithoutManualRefresh() async {
        channels.stored = [makeChannel("1", "TRT 1")]

        let viewModel = makeViewModel()
        await viewModel.load()
        await waitUntil("ilk liste gelmeli") { viewModel.channels.count == 1 }

        // ⚠️ Abone olunmadan yayın yapmak kaybolur — süre değil, aboneliği bekle.
        await waitUntil("gözlem başlamalı") { channels.isObserving }

        // Senkronizasyon yeni kanal yazdı.
        channels.emit([makeChannel("1", "TRT 1"), makeChannel("2", "Yeni")])

        await waitUntil("gözlem ekranı tazelemeli") { viewModel.channels.count == 2 }
    }

    // MARK: - Yardımcılar

    private func makeChannel(
        _ id: String,
        _ name: String,
        epgID: String? = nil,
        number: Int? = nil
    ) -> Channel {
        Channel(
            id: Channel.ID(id),
            playlistID: "p1",
            name: name,
            streamKey: id,
            epgChannelID: epgID,
            number: number
        )
    }

    private func makeAdultChannel(_ id: String, _ name: String, number: Int? = nil) -> Channel {
        Channel(
            id: Channel.ID(id),
            playlistID: "p1",
            name: name,
            streamKey: id,
            number: number,
            isAdult: true
        )
    }

    private func makeProgram(_ title: String) -> EPGProgram {
        let start = Date()
        return EPGProgram(
            id: EPGProgram.ID(title),
            epgChannelID: "trt1.tr",
            title: title,
            startDate: start,
            endDate: start.addingTimeInterval(3_600)
        )
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
    /// Numarayla geçiş testleri için.
    var byNumber: [Int: Channel] = [:]
    private(set) var numberLookups: [Int] = []

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

    func channel(number: Int, playlistID: Playlist.ID) async throws -> Channel? {
        numberLookups.append(number)
        return byNumber[number]
    }

    func search(query: String, playlistID: Playlist.ID, limit: Int) async throws -> [Channel] {
        searchQueries.append(query)
        return searchResults
    }

    /// Abone olundu mu? Test, yayın yapmadan önce bunu bekler.
    private(set) var isObserving = false

    func observeChannels(
        playlistID: Playlist.ID,
        categoryID: MediaCategory.ID?
    ) -> AsyncStream<[Channel]> {
        observedCategoryIDs.append(categoryID)
        return AsyncStream { continuation in
            self.continuation = continuation
            self.isObserving = true
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

    func isFavorite(_ target: FavoriteTarget) async throws -> Bool {
        keys.contains(target.storageKey)
    }

    func toggle(_ target: FavoriteTarget) async throws -> Bool {
        let key = target.storageKey
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

private final class StubHistory: WatchHistoryRepository, @unchecked Sendable {

    var channels: [Channel] = []

    func record(_ source: PlaybackItem.Source, at date: Date) async throws {}
    func recentChannels(playlistID: Playlist.ID, limit: Int) async throws -> [Channel] {
        Array(channels.prefix(limit))
    }
    func clearAll() async throws {}
}

private final class StubParental: ParentalControlling, @unchecked Sendable {

    var enabled = false
    var unlocked = true

    func isEnabled() async -> Bool { enabled }
    func isUnlocked() async -> Bool { unlocked }
    func setPIN(_ pin: String) async throws { enabled = true }
    @discardableResult func unlock(with pin: String) async -> Bool { unlocked = true; return true }
    func lock() async { unlocked = false }
    func disable(with pin: String) async throws { enabled = false }
}

private final class StubEPG: EPGRepository, @unchecked Sendable {

    var programs: [String: EPGProgram] = [:]

    func nowPlaying(epgChannelID: String, at date: Date) async throws -> EPGProgram? {
        programs[epgChannelID]
    }

    func nowPlaying(epgChannelIDs: [String], at date: Date) async throws -> [String: EPGProgram] {
        programs.filter { epgChannelIDs.contains($0.key) }
    }

    func allNowPlaying(at date: Date) async throws -> [String: EPGProgram] { programs }

    func programs(epgChannelID: String, from: Date, to: Date) async throws -> [EPGProgram] { [] }
    func purgePrograms(before date: Date) async throws {}
}
