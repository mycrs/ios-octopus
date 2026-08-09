import Foundation
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
