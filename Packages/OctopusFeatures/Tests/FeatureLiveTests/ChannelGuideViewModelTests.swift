import XCTest
import OctopusDomain
@testable import FeatureLive

/// Kanal rehberi: gün seçimi, program durumları.
@MainActor
final class ChannelGuideViewModelTests: XCTestCase {

    private var channels: GuideStubChannels!
    private var epg: GuideStubEPG!

    /// Sabit "şimdi": 2026-08-05 12:00 UTC
    private let now = Date(timeIntervalSince1970: 1_785_931_200)

    override func setUp() async throws {
        channels = GuideStubChannels()
        epg = GuideStubEPG()
    }

    private func makeViewModel(channelID: Channel.ID = "c1") -> ChannelGuideViewModel {
        ChannelGuideViewModel(
            channelID: channelID,
            dependencies: LiveDependencies(
                playlists: GuideStubPlaylists(),
                channels: channels,
                epg: epg,
                favorites: GuideStubFavorites()
            ),
            now: { self.now }
        )
    }

    private func makeProgram(
        title: String,
        startOffsetHours: Double,
        durationHours: Double = 1
    ) -> EPGProgram {
        let start = now.addingTimeInterval(startOffsetHours * 3_600)
        return EPGProgram(
            id: EPGProgram.ID(title),
            epgChannelID: "trt1.tr",
            title: title,
            startDate: start,
            endDate: start.addingTimeInterval(durationHours * 3_600)
        )
    }

    private func makeChannel(epgID: String? = "trt1.tr") -> Channel {
        Channel(
            id: "c1",
            playlistID: "p1",
            name: "TRT 1",
            streamKey: "1",
            epgChannelID: epgID
        )
    }

    // MARK: - Program durumları

    func test_marksCurrentPastAndFuturePrograms() async {
        channels.stored = [makeChannel()]
        epg.programs = [
            makeProgram(title: "Biten", startOffsetHours: -3),
            makeProgram(title: "Şimdi", startOffsetHours: -0.5, durationHours: 2),
            makeProgram(title: "Sonraki", startOffsetHours: 2)
        ]

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertEqual(viewModel.entries.count, 3)

        let ended = viewModel.entries[0]
        XCTAssertTrue(ended.hasEnded)
        XCTAssertFalse(ended.isOnAir)
        XCTAssertNil(ended.progress)

        let current = viewModel.entries[1]
        XCTAssertTrue(current.isOnAir)
        XCTAssertFalse(current.hasEnded)
        XCTAssertEqual(current.progress ?? 0, 0.25, accuracy: 0.01)

        let upcoming = viewModel.entries[2]
        XCTAssertFalse(upcoming.isOnAir)
        XCTAssertFalse(upcoming.hasEnded)
    }

    func test_channelWithoutEPGIDShowsEmptyNotError() async {
        // Rehber kimliği olmayan kanal yaygın; bu bir hata değil.
        channels.stored = [makeChannel(epgID: nil)]

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertTrue(viewModel.entries.isEmpty)
        XCTAssertEqual(viewModel.state, .loaded(0))
    }

    func test_missingChannelReportsNotFound() async {
        let viewModel = makeViewModel(channelID: "yok")
        await viewModel.load()

        XCTAssertEqual(viewModel.state, .failed(.notFound))
    }

    // MARK: - Gün gezinme

    func test_dayTitlesAreHumanReadable() async {
        channels.stored = [makeChannel()]

        let viewModel = makeViewModel()
        await viewModel.load()
        XCTAssertEqual(viewModel.dayTitle, "Bugün")

        await viewModel.changeDay(by: 1)
        XCTAssertEqual(viewModel.dayTitle, "Yarın")

        await viewModel.changeDay(by: -2)
        XCTAssertEqual(viewModel.dayTitle, "Dün")
    }

    func test_dayNavigationIsBounded() async {
        // Rehber sınırlı bir aralığı kapsar; boş günlere sonsuz
        // kaydırılmamalı.
        channels.stored = [makeChannel()]

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertTrue(viewModel.canGoBack)
        await viewModel.changeDay(by: -1)
        XCTAssertFalse(viewModel.canGoBack, "Dünden geriye gidilememeli")

        await viewModel.changeDay(by: 7)
        XCTAssertFalse(viewModel.canGoForward)
    }

    func test_dayChangeRequestsNewRange() async {
        channels.stored = [makeChannel()]

        let viewModel = makeViewModel()
        await viewModel.load()
        let firstRange = epg.requestedRanges.last

        await viewModel.changeDay(by: 1)
        let secondRange = epg.requestedRanges.last

        XCTAssertNotEqual(firstRange?.from, secondRange?.from)
        XCTAssertEqual(
            secondRange!.from.timeIntervalSince(firstRange!.from),
            86_400,
            accuracy: 1
        )
    }

    // MARK: - Saat biçimi

    func test_timeTextIsTwentyFourHour() {
        let viewModel = makeViewModel()
        // 12:00 UTC — biçimlendirici cihaz saat dilimini kullanır,
        // burada yalnızca "SS:dd" desenini doğruluyoruz.
        let text = viewModel.timeText(now)
        XCTAssertEqual(text.count, 5)
        XCTAssertTrue(text.contains(":"))
    }
}

// MARK: - Sahteler

private final class GuideStubChannels: ChannelRepository, @unchecked Sendable {

    var stored: [Channel] = []

    func categories(playlistID: Playlist.ID) async throws -> [MediaCategory] { [] }
    func channels(playlistID: Playlist.ID, categoryID: MediaCategory.ID?) async throws -> [Channel] { stored }
    func channel(id: Channel.ID) async throws -> Channel? { stored.first { $0.id == id } }
    func channel(number: Int, playlistID: Playlist.ID) async throws -> Channel? {
        stored.first { $0.number == number }
    }
    func search(query: String, playlistID: Playlist.ID, limit: Int) async throws -> [Channel] { [] }
    func observeChannels(
        playlistID: Playlist.ID,
        categoryID: MediaCategory.ID?
    ) -> AsyncStream<[Channel]> {
        AsyncStream { $0.finish() }
    }
}

private final class GuideStubEPG: EPGRepository, @unchecked Sendable {

    var programs: [EPGProgram] = []
    private(set) var requestedRanges: [(from: Date, to: Date)] = []

    func nowPlaying(epgChannelID: String, at date: Date) async throws -> EPGProgram? { nil }
    func nowPlaying(epgChannelIDs: [String], at date: Date) async throws -> [String: EPGProgram] { [:] }
    func allNowPlaying(at date: Date) async throws -> [String: EPGProgram] { [:] }

    func programs(epgChannelID: String, from: Date, to: Date) async throws -> [EPGProgram] {
        requestedRanges.append((from, to))
        return programs
    }

    func purgePrograms(before date: Date) async throws {}
}

private struct GuideStubPlaylists: PlaylistRepository {
    func all() async throws -> [Playlist] { [] }
    func playlist(id: Playlist.ID) async throws -> Playlist? { nil }
    func activePlaylist() async throws -> Playlist? { nil }
    func add(_ playlist: Playlist, password: String?) async throws {}
    func update(_ playlist: Playlist) async throws {}
    func setActive(id: Playlist.ID) async throws {}
    func delete(id: Playlist.ID) async throws {}
}

private struct GuideStubFavorites: FavoritesRepository {
    func isFavorite(_ target: FavoriteTarget) async throws -> Bool { false }
    func toggle(_ target: FavoriteTarget) async throws -> Bool { false }
    func favoriteChannels(playlistID: Playlist.ID) async throws -> [Channel] { [] }
    func favoriteMovies(playlistID: Playlist.ID) async throws -> [Movie] { [] }
    func favoriteSeries(playlistID: Playlist.ID) async throws -> [Series] { [] }
    func observeFavoriteKeys() -> AsyncStream<Set<String>> { AsyncStream { $0.finish() } }
}
