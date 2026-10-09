import Foundation
import UIKit
import OctopusDomain
import OctopusPlayback

/// Canlı TV testleri için oynatma sahteleri.
///
/// `LiveDependencies` gömülü mini oynatıcı yüzünden bir motor çözücü ve
/// akış çözümleyici istiyor. Bu testler oynatmayı sınamıyor; buradaki
/// sahteler yalnızca sözleşmeyi karşılıyor.
///
/// ⚠️ `LiveDependencies` bu üçüne **varsayılan değer vermiyor**, kasıtlı:
/// varsayılan olsaydı `AppContainer`'da bağlamayı unutmak sessizce
/// çalışmayan bir mini oynatıcı üretirdi. Testin biraz daha yazması,
/// üretimde sessiz bir hatadan iyidir.
enum LiveTestPlayback {

    /// Hiçbir şey oynatmayan çözücü.
    @MainActor
    static func makeResolver() -> PlaybackEngineResolver {
        PlaybackEngineResolver(native: { NullPlaybackEngine() })
    }

    /// Ekran bağımlılığındaki paylaşılan denetleyiciyi test depolarıyla kurar.
    @MainActor
    static func makeController(
        progress: PlaybackProgressRepository,
        history: WatchHistoryRepository
    ) -> PlayerController {
        PlayerController(
            resolver: makeResolver(),
            progress: progress,
            history: history,
            setScreenAwake: { _ in }
        )
    }
}

final class LiveStubStreams: StreamResolving, @unchecked Sendable {

    func playbackItem(for channel: Channel) async throws -> PlaybackItem {
        PlaybackItem(
            source: .liveChannel(channel.id),
            url: URL(string: "http://example.com/live.ts") ?? URL(fileURLWithPath: "/"),
            title: channel.name,
            isLive: true
        )
    }

    func playbackItem(for movie: Movie) async throws -> PlaybackItem {
        throw AppError.notFound
    }

    func playbackItem(for episode: Episode, in series: Series) async throws -> PlaybackItem {
        throw AppError.notFound
    }
}

final class LiveStubProgress: PlaybackProgressRepository, @unchecked Sendable {

    func progress(for source: PlaybackItem.Source) async throws -> PlaybackProgress? { nil }
    func save(_ progress: PlaybackProgress, for source: PlaybackItem.Source) async throws {}

    func continueWatching(
        playlistID: Playlist.ID,
        limit: Int
    ) async throws -> [PlaybackProgress] { [] }

    func clear(for source: PlaybackItem.Source) async throws {}
    func clearAll() async throws {}
}

/// Controllable public engine events exercise the real controller/projection path.
@MainActor
final class LiveObservationTestEngine: PlaybackEngine {
    let identifier = "observation-test"
    let events: AsyncStream<PlaybackEvent>
    private let continuation: AsyncStream<PlaybackEvent>.Continuation
    let surface = UIView()
    private(set) var currentState: PlaybackState = .idle
    private(set) var loadCount = 0
    private(set) var playCount = 0
    private(set) var teardownCount = 0
    let audioTracks: [MediaTrack] = []
    let subtitleTracks: [MediaTrack] = []
    let selectedAudioTrack: MediaTrack? = nil
    let selectedSubtitleTrack: MediaTrack? = nil
    let supportsPictureInPicture = false
    let supportsAirPlay = false
    let isPictureInPicturePossible = false

    init() {
        var captured: AsyncStream<PlaybackEvent>.Continuation?
        events = AsyncStream { captured = $0 }
        guard let captured else { preconditionFailure("AsyncStream did not initialize its continuation") }
        continuation = captured
    }

    func emit(_ event: PlaybackEvent) {
        if case .stateChanged(let state) = event { currentState = state }
        continuation.yield(event)
    }

    func load(_ item: PlaybackItem) async { loadCount += 1 }
    func play() { playCount += 1; emit(.stateChanged(.playing)) }
    func pause() { emit(.stateChanged(.paused)) }
    func stop() { emit(.stateChanged(.idle)) }
    func seek(to seconds: TimeInterval) async {}
    func setVolume(_ volume: Float) {}
    func setRate(_ rate: Float) {}
    func select(track: MediaTrack) {}
    func setVideoFit(_ fit: VideoFit) {}
    func setPictureInPictureActive(_ active: Bool) {}
    func makeVideoView() -> UIView { surface }
    func teardown() { teardownCount += 1; continuation.finish() }
}

final class LiveObservationTestHistory: WatchHistoryRepository, @unchecked Sendable {
    func record(_ source: PlaybackItem.Source, at date: Date) async throws {}
    func recentChannels(playlistID: Playlist.ID, limit: Int) async throws -> [Channel] { [] }
    func clearAll() async throws {}
}
