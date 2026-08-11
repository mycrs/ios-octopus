import XCTest
import OctopusDomain
import OctopusPlayback
@testable import FeaturePlayer

/// Oynatıcıdan kanal değiştirme.
///
/// ⚠️ Buradaki en kritik test **kilit** testidir: zaplama listesi
/// süzülmezse kullanıcı oynatıcıda ileri geri basarak yetişkin bir kanala
/// düşer ve ebeveyn kilidi bu yoldan atlatılmış olur. Kilit tek yerde
/// tutulup yedi yerde uygulanıyor; burası yedincisi.
@MainActor
final class PlayerZappingTests: XCTestCase {

    private let playlistID: Playlist.ID = "p1"

    // MARK: - Sıra

    func test_zapMovesToNextChannel() async {
        let viewModel = makeViewModel(startingAt: "c1")
        await viewModel.resolve()

        await viewModel.zap(by: 1)

        XCTAssertEqual(title(of: viewModel), "İkinci")
    }

    func test_zapMovesToPreviousChannel() async {
        let viewModel = makeViewModel(startingAt: "c2")
        await viewModel.resolve()

        await viewModel.zap(by: -1)

        XCTAssertEqual(title(of: viewModel), "Birinci")
    }

    /// IPTV kumandalarının alışılmış davranışı: sonda durmaz, başa döner.
    func test_zapWrapsAround() async {
        let viewModel = makeViewModel(startingAt: "c1")
        await viewModel.resolve()

        await viewModel.zap(by: -1)

        XCTAssertEqual(title(of: viewModel), "Üçüncü", "Baştan geriye gidince sona sarmalı")
    }

    // MARK: - Ebeveyn kilidi

    /// Kilit açıkken yetişkin kanal **listede olmamalı**.
    func test_zapSkipsAdultChannelsWhenLocked() async {
        let parental = StubParental()
        parental.enabled = true
        parental.unlocked = false

        let viewModel = makeViewModel(startingAt: "c1", parental: parental)
        await viewModel.resolve()

        // c2 yetişkin: bir adım ileri gitmek doğrudan c3'e götürmeli.
        await viewModel.zap(by: 1)

        XCTAssertEqual(
            title(of: viewModel), "Üçüncü",
            "Kilitliyken yetişkin kanala zaplanabiliyor — kilit atlatıldı"
        )
    }

    func test_zapIncludesAdultChannelsWhenUnlocked() async {
        let parental = StubParental()
        parental.enabled = true
        parental.unlocked = true

        let viewModel = makeViewModel(startingAt: "c1", parental: parental)
        await viewModel.resolve()
        await viewModel.zap(by: 1)

        XCTAssertEqual(title(of: viewModel), "İkinci")
    }

    func test_directProtectedChannelCannotBypassLock() async {
        let parental = StubParental()
        parental.enabled = true
        parental.unlocked = false

        let viewModel = makeViewModel(startingAt: "c2", parental: parental)
        await viewModel.resolve()

        guard case .failed = viewModel.phase else {
            return XCTFail("Korumalı kanal doğrudan kimlikle açılabildi")
        }
    }

    func test_backgroundLockStopsProtectedSourceButAllowsNormalSource() async {
        let parental = StubParental()
        parental.enabled = true
        parental.unlocked = true

        let protected = makeViewModel(startingAt: "c2", parental: parental)
        await protected.resolve()
        let protectedAllowed = await protected.lockAndValidateCurrentSource()
        XCTAssertFalse(protectedAllowed)

        parental.unlocked = true
        let normal = makeViewModel(startingAt: "c1", parental: parental)
        await normal.resolve()
        let normalAllowed = await normal.lockAndValidateCurrentSource()
        XCTAssertTrue(normalAllowed)
    }

    // MARK: - Kullanılabilirlik

    func test_zappingIsUnavailableForMovies() async {
        let viewModel = makeViewModel(movie: true)
        await viewModel.resolve()

        XCTAssertFalse(viewModel.canZap, "Filmde sonraki kanal diye bir şey yok")
    }

    /// Tek kanallı kaynakta düğme gösterilmemeli — hiçbir yere götürmez.
    func test_zappingIsUnavailableWithSingleChannel() async {
        let viewModel = makeViewModel(startingAt: "c1", channelCount: 1)
        await viewModel.resolve()

        XCTAssertFalse(viewModel.canZap)
    }

    func test_explicitStartPosition_isAppliedToVOD() async {
        let viewModel = makeViewModel(movie: true, startAt: 125)

        await viewModel.resolve()

        guard case .ready(let item) = viewModel.phase else {
            return XCTFail("Film çözümlenemedi")
        }
        XCTAssertEqual(item.resumeAt, 125)
    }

    // MARK: - Yardımcılar

    private func title(of viewModel: PlayerViewModel) -> String? {
        guard case .ready(let item) = viewModel.phase else { return nil }
        return item.title
    }

    private func makeViewModel(
        startingAt rawID: String = "c1",
        channelCount: Int = 3,
        parental: ParentalControlling = OpenParentalControl(),
        movie: Bool = false,
        startAt: TimeInterval? = nil
    ) -> PlayerViewModel {
        let channels = StubChannels(channels: makeChannels(count: channelCount))

        let dependencies = PlayerDependencies(
            resolver: PlaybackEngineResolver(native: { NullPlaybackEngine() }),
            streams: StubStreams(),
            progress: StubProgress(),
            history: StubHistory(),
            channels: channels,
            vod: StubVOD(),
            series: StubSeries(),
            parental: parental
        )

        return PlayerViewModel(
            dependencies: dependencies,
            source: movie ? .movie(Movie.ID("m1")) : .liveChannel(Channel.ID(rawID)),
            startAt: startAt
        )
    }

    private func makeChannels(count: Int) -> [Channel] {
        let names = ["Birinci", "İkinci", "Üçüncü"]
        return (0..<count).map { index in
            Channel(
                id: Channel.ID("c\(index + 1)"),
                playlistID: playlistID,
                name: names[index],
                streamKey: "\(index)",
                // İkinci kanal yetişkin — kilit testinin dayanağı.
                isAdult: index == 1
            )
        }
    }
}

// MARK: - Test ikizleri

final class StubChannels: ChannelRepository, @unchecked Sendable {

    let channels: [Channel]

    init(channels: [Channel]) { self.channels = channels }

    func categories(playlistID: Playlist.ID) async throws -> [MediaCategory] { [] }

    func channels(
        playlistID: Playlist.ID,
        categoryID: MediaCategory.ID?
    ) async throws -> [Channel] { channels }

    func channel(id: Channel.ID) async throws -> Channel? {
        channels.first { $0.id == id }
    }

    func channel(number: Int, playlistID: Playlist.ID) async throws -> Channel? { nil }

    func search(query: String, playlistID: Playlist.ID, limit: Int) async throws -> [Channel] { [] }

    func observeChannels(
        playlistID: Playlist.ID,
        categoryID: MediaCategory.ID?
    ) -> AsyncStream<[Channel]> {
        AsyncStream { $0.finish() }
    }
}

struct StubStreams: StreamResolving {

    func playbackItem(for channel: Channel) async throws -> PlaybackItem {
        PlaybackItem(
            source: .liveChannel(channel.id),
            url: URL(fileURLWithPath: "/dev/null"),
            title: channel.name,
            isLive: true
        )
    }

    func playbackItem(for movie: Movie) async throws -> PlaybackItem {
        PlaybackItem(
            source: .movie(movie.id),
            url: URL(fileURLWithPath: "/dev/null"),
            title: movie.title,
            isLive: false
        )
    }

    func playbackItem(for episode: Episode, in series: Series) async throws -> PlaybackItem {
        PlaybackItem(
            source: .episode(episode.id),
            url: URL(fileURLWithPath: "/dev/null"),
            title: episode.title,
            isLive: false
        )
    }
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

struct StubProgress: PlaybackProgressRepository {
    func progress(for source: PlaybackItem.Source) async throws -> PlaybackProgress? { nil }
    func save(_ progress: PlaybackProgress, for source: PlaybackItem.Source) async throws {}
    func continueWatching(playlistID: Playlist.ID, limit: Int) async throws -> [PlaybackProgress] { [] }
    func clear(for source: PlaybackItem.Source) async throws {}
    func clearAll() async throws {}
}

struct StubHistory: WatchHistoryRepository {
    func record(_ source: PlaybackItem.Source, at date: Date) async throws {}
    func recentChannels(playlistID: Playlist.ID, limit: Int) async throws -> [Channel] { [] }
    func clearAll() async throws {}
}

struct StubVOD: VODRepository {
    func categories(playlistID: Playlist.ID) async throws -> [MediaCategory] { [] }
    func movies(
        playlistID: Playlist.ID,
        categoryID: MediaCategory.ID?,
        limit: Int,
        offset: Int
    ) async throws -> [Movie] { [] }
    func movie(id: Movie.ID) async throws -> Movie? {
        Movie(id: id, playlistID: "p1", title: "Film", streamKey: "m")
    }
    func loadDetails(id: Movie.ID) async throws -> Movie {
        Movie(id: id, playlistID: "p1", title: "Film", streamKey: "m")
    }
    func search(query: String, playlistID: Playlist.ID, limit: Int) async throws -> [Movie] { [] }
    func recentlyAdded(playlistID: Playlist.ID, limit: Int) async throws -> [Movie] { [] }
}

struct StubSeries: SeriesRepository {
    let storedEpisodes: [Episode]

    init(episodes: [Episode] = []) {
        storedEpisodes = episodes
    }

    func categories(playlistID: Playlist.ID) async throws -> [MediaCategory] { [] }
    func series(
        playlistID: Playlist.ID,
        categoryID: MediaCategory.ID?,
        limit: Int,
        offset: Int
    ) async throws -> [Series] { [] }
    func series(id: Series.ID) async throws -> Series? {
        guard storedEpisodes.contains(where: { $0.seriesID == id }) else { return nil }
        return Series(id: id, playlistID: "p1", title: "Dizi", streamKey: "series")
    }
    func seasons(seriesID: Series.ID) async throws -> [Season] {
        Set(storedEpisodes.filter { $0.seriesID == seriesID }.map(\.seasonNumber))
            .sorted()
            .map { number in
                Season(
                    id: Season.ID("season-\(number)"),
                    seriesID: seriesID,
                    number: number
                )
            }
    }
    func episodes(seriesID: Series.ID, seasonNumber: Int) async throws -> [Episode] {
        storedEpisodes.filter {
            $0.seriesID == seriesID && $0.seasonNumber == seasonNumber
        }
    }
    func episode(id: Episode.ID) async throws -> Episode? {
        storedEpisodes.first { $0.id == id }
    }
    func loadDetails(id: Series.ID) async throws {}
    func invalidateDetails(id: Series.ID) async throws {}
    func search(query: String, playlistID: Playlist.ID, limit: Int) async throws -> [Series] { [] }
    func recentlyAdded(playlistID: Playlist.ID, limit: Int) async throws -> [Series] { [] }
}
