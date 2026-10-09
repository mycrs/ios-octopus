import XCTest
import OctopusDomain
@testable import OctopusData

final class SubscriptionResolverTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func fixture(
        status: SubscriptionStatus?, expiresAt: Date?, kind: Playlist.Kind = .sampleLibrary
    ) -> (ProviderStreamResolver, InMemoryPlaylistRepository, SubscriptionResolverFactory) {
        let playlists = InMemoryPlaylistRepository(seed: [Playlist(
            id: "p", name: "Source", kind: kind, createdAt: now,
            expiresAt: expiresAt, subscriptionStatus: status
        )])
        let factory = SubscriptionResolverFactory()
        let date = now
        return (
            ProviderStreamResolver(
                playlists: playlists, providerFactory: factory,
                progress: InMemoryPlaybackProgressRepository(), now: { date }
            ), playlists, factory
        )
    }

    private var channel: Channel {
        Channel(id: "c", playlistID: "p", name: "Channel", streamKey: "https://media.example/movie.mp4")
    }

    func test_everyPlaybackKindRejectsKnownBlockBeforeProviderCreation() async throws {
        for status in [SubscriptionStatus.active, .expired, .inactive, .disabled, .banned] {
            let deadline = status == .active ? now : nil
            let (resolver, _, factory) = fixture(status: status, expiresAt: deadline)
            let block = try XCTUnwrap(SubscriptionAccessBlock.evaluate(status: status, expiresAt: deadline, at: now))
            let movie = Movie(id: "m", playlistID: "p", title: "Movie", streamKey: "1")
            let series = Series(id: "s", playlistID: "p", title: "Series", streamKey: "1")
            let episode = Episode(id: "e", seriesID: "s", seasonNumber: 1, number: 1, title: "Episode", streamKey: "1")
            do {
                _ = try await resolver.playbackItem(for: channel)
                XCTFail("Blocked live source must not resolve")
            } catch { XCTAssertEqual(error as? AppError, .subscriptionUnavailable(block)) }
            do {
                _ = try await resolver.playbackItem(for: movie)
                XCTFail("Blocked movie source must not resolve")
            } catch { XCTAssertEqual(error as? AppError, .subscriptionUnavailable(block)) }
            do {
                _ = try await resolver.playbackItem(for: episode, in: series)
                XCTFail("Blocked episode source must not resolve")
            } catch { XCTAssertEqual(error as? AppError, .subscriptionUnavailable(block)) }
            let calls = await factory.calls
            XCTAssertEqual(calls, 0, "Known block must not even construct a provider or resolve its host")
        }
    }

    func test_nilExpirationKeepsM3UAndSampleSourcesAvailable() async throws {
        let m3u = Playlist.Kind.m3u(url: try XCTUnwrap(URL(string: "https://list.example/list.m3u")))
        for kind in [m3u, .sampleLibrary] {
            let (resolver, _, factory) = fixture(status: nil, expiresAt: nil, kind: kind)
            let item = try await resolver.playbackItem(for: channel)
            XCTAssertEqual(item.source, .liveChannel(channel.id))
            let calls = await factory.calls
            XCTAssertEqual(calls, 1)
        }
    }

    func test_resolverReadsRenewedMetadataInsteadOfRetainingOldBlock() async throws {
        let (resolver, playlists, factory) = fixture(status: .expired, expiresAt: now)
        do {
            _ = try await resolver.playbackItem(for: channel)
            XCTFail("Old account must be blocked")
        } catch { XCTAssertEqual(error as? AppError, .subscriptionUnavailable(
            SubscriptionAccessBlock(status: .expired, expiresAt: now)
        )) }
        try await playlists.updateSubscription(id: "p", status: .active, expiresAt: now.addingTimeInterval(1))
        let item = try await resolver.playbackItem(for: channel)
        XCTAssertEqual(item.title, channel.name)
        let calls = await factory.calls
        XCTAssertEqual(calls, 1)
    }

    func test_expirationDuringProviderCreationCannotReturnAnOldPlayableURL() async throws {
        let deadline = now.addingTimeInterval(1)
        let clock = SubscriptionResolverClock(now)
        let playlists = InMemoryPlaylistRepository(seed: [Playlist(
            id: "p", name: "Source", kind: .sampleLibrary, createdAt: now,
            expiresAt: deadline, subscriptionStatus: .active
        )])
        let factory = SubscriptionResolverFactory(beforeBuild: { clock.set(deadline) })
        let resolver = ProviderStreamResolver(
            playlists: playlists, providerFactory: factory,
            progress: InMemoryPlaybackProgressRepository(), now: { clock.value }
        )
        do {
            _ = try await resolver.playbackItem(for: channel)
            XCTFail("Factory completion at the deadline must not expose a playable URL")
        } catch {
            XCTAssertEqual(error as? AppError, .subscriptionUnavailable(
                SubscriptionAccessBlock(status: .expired, expiresAt: deadline)
            ))
        }
        let calls = await factory.calls
        XCTAssertEqual(calls, 1)
    }

    func test_movieAndEpisodeProgressAwaitCannotPassTheExpirationBoundary() async throws {
        let deadline = now.addingTimeInterval(1)
        let provider = XtreamContentProvider(
            baseURL: try XCTUnwrap(URL(string: "https://provider.example")),
            username: "fixture", password: "fixture", playlistID: "p",
            httpClient: StubHTTPClient { _ in throw AppError.network(reason: "Unexpected request") }
        )
        for isEpisode in [false, true] {
            let clock = SubscriptionResolverClock(now)
            let playlists = InMemoryPlaylistRepository(seed: [Playlist(
                id: "p", name: "Source", kind: .sampleLibrary, createdAt: now,
                expiresAt: deadline, subscriptionStatus: .active
            )])
            let resolver = ProviderStreamResolver(
                playlists: playlists, providerFactory: FakeProviderFactory(provider: provider),
                progress: SubscriptionDeadlineProgress(afterRead: { clock.set(deadline) }),
                now: { clock.value }
            )
            do {
                if isEpisode {
                    let series = Series(id: "s", playlistID: "p", title: "Series", streamKey: "1")
                    let episode = Episode(id: "e", seriesID: "s", seasonNumber: 1, number: 1, title: "Episode", streamKey: "1", containerExtension: "mp4")
                    _ = try await resolver.playbackItem(for: episode, in: series)
                } else {
                    _ = try await resolver.playbackItem(for: Movie(id: "m", playlistID: "p", title: "Movie", streamKey: "1"))
                }
                XCTFail("Progress lookup crossing the deadline must not return a playable URL")
            } catch {
                XCTAssertEqual(error as? AppError, .subscriptionUnavailable(
                    SubscriptionAccessBlock(status: .expired, expiresAt: deadline)
                ))
            }
            XCTAssertEqual(clock.value, deadline, "The resume lookup must actually have run")
        }
    }
}

private actor SubscriptionResolverFactory: ContentProviderFactory {
    private(set) var calls = 0
    private let provider = FakeProvider(channels: [])
    private let beforeBuild: (@Sendable () -> Void)?

    init(beforeBuild: (@Sendable () -> Void)? = nil) { self.beforeBuild = beforeBuild }

    func makeProvider(for playlist: Playlist) async throws -> ContentProvider {
        calls += 1
        beforeBuild?()
        return provider
    }
}

private final class SubscriptionResolverClock: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Date

    init(_ value: Date) { stored = value }

    var value: Date {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ value: Date) {
        lock.lock()
        defer { lock.unlock() }
        stored = value
    }
}

private struct SubscriptionDeadlineProgress: PlaybackProgressRepository {
    let afterRead: @Sendable () -> Void
    func progress(for source: PlaybackItem.Source) async throws -> PlaybackProgress? {
        afterRead()
        return nil
    }
    func save(_ progress: PlaybackProgress, for source: PlaybackItem.Source) async throws {}
    func continueWatching(playlistID: Playlist.ID, limit: Int) async throws -> [PlaybackProgress] { [] }
    func clear(for source: PlaybackItem.Source) async throws {}
    func clearAll() async throws {}
}
