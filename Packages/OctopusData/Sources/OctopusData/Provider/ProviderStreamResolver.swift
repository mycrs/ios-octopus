import Foundation
import OctopusCore
import OctopusDomain

/// İçerikten oynatılabilir akışa geçiş.
///
/// Akış adresi kaynağa göre tamamen farklı kurulur:
/// - Xtream: `{taban}/live/{kullanıcı}/{parola}/{stream_id}.m3u8`
/// - M3U: listedeki adresin kendisi
///
/// Bu farkı yalnızca burası bilir. Ekranlar `PlaybackItem` alır ve
/// oynatıcıya verir; kaynağın türünü hiç görmez.
public struct ProviderStreamResolver: StreamResolving {

    private let playlists: PlaylistRepository
    private let providerFactory: ContentProviderFactory
    private let progress: PlaybackProgressRepository

    public init(
        playlists: PlaylistRepository,
        providerFactory: ContentProviderFactory,
        progress: PlaybackProgressRepository
    ) {
        self.playlists = playlists
        self.providerFactory = providerFactory
        self.progress = progress
    }

    // MARK: - Canlı yayın

    public func playbackItem(for channel: Channel) async throws -> PlaybackItem {
        let provider = try await provider(for: channel.playlistID)

        guard let url = provider.streamURL(for: channel) else {
            throw AppError.playbackFailed(reason: "Kanal adresi kurulamadı")
        }

        return PlaybackItem(
            source: .liveChannel(channel.id),
            url: url,
            title: channel.name,
            artworkURL: channel.logoURL,
            isLive: true,
            // Paneller User-Agent denetler; motor bu başlığı iletmek zorunda.
            headers: provider.streamHeaders
        )
    }

    // MARK: - Film

    public func playbackItem(for movie: Movie) async throws -> PlaybackItem {
        let provider = try await provider(for: movie.playlistID)

        guard let url = provider.streamURL(for: movie) else {
            throw AppError.playbackFailed(reason: "Film adresi kurulamadı")
        }

        // Kaldığı yerden devam: bitmiş içerik baştan başlar.
        let source = PlaybackItem.Source.movie(movie.id)
        let stored = try? await progress.progress(for: source)
        let resumeAt = (stored?.isFinished == false) ? stored?.positionSeconds : nil

        return PlaybackItem(
            source: source,
            url: url,
            title: movie.title,
            subtitle: movie.releaseYearText,
            artworkURL: movie.posterURL,
            isLive: false,
            resumeAt: resumeAt,
            headers: provider.streamHeaders
        )
    }

    // MARK: - Dizi bölümü

    public func playbackItem(for episode: Episode, in series: Series) async throws -> PlaybackItem {
        let provider = try await provider(for: series.playlistID)

        guard let url = provider.streamURL(for: episode) else {
            throw AppError.playbackFailed(reason: "Bölüm adresi kurulamadı")
        }

        let source = PlaybackItem.Source.episode(episode.id)
        let stored = try? await progress.progress(for: source)
        let resumeAt = (stored?.isFinished == false) ? stored?.positionSeconds : nil

        return PlaybackItem(
            source: source,
            url: url,
            title: episode.title,
            // "Dizi Adı · S02B07"
            subtitle: "\(series.title) · \(episode.shortLabel)",
            artworkURL: episode.stillURL ?? series.posterURL,
            isLive: false,
            resumeAt: resumeAt,
            headers: provider.streamHeaders
        )
    }

    // MARK: - Yardımcı

    private func provider(for playlistID: Playlist.ID) async throws -> ContentProvider {
        guard let playlist = try await playlists.playlist(id: playlistID) else {
            // Kaynak silinmiş ama ekran hâlâ açık olabilir.
            throw AppError.notFound
        }
        return try await providerFactory.makeProvider(for: playlist)
    }
}

private extension Movie {
    /// Detay satırında gösterilecek yıl bilgisi.
    var releaseYearText: String? {
        guard let releaseDate else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return String(calendar.component(.year, from: releaseDate))
    }
}
