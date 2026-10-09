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
    private let now: @Sendable () -> Date

    public init(
        playlists: PlaylistRepository,
        providerFactory: ContentProviderFactory,
        progress: PlaybackProgressRepository,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.playlists = playlists
        self.providerFactory = providerFactory
        self.progress = progress
        self.now = now
    }

    // MARK: - Canlı yayın

    public func playbackItem(for channel: Channel) async throws -> PlaybackItem {
        let source = try await providerContext(for: channel.playlistID)
        let provider = source.provider
        // Örnek kanallar sonlu, kayıtlı filmdir. Gerçek canlı yayın gibi
        // tekrar bağlanma/sonsuz oynatma davranışı veya etiketi verilmez.
        let isRecordedSample = source.playlist.kind == .sampleLibrary

        guard let url = provider.streamURL(for: channel) else {
            throw AppError.playbackFailed(reason: "Kanal adresi kurulamadı")
        }

        return PlaybackItem(
            source: .liveChannel(channel.id),
            url: url,
            title: channel.name,
            artworkURL: channel.logoURL,
            isLive: !isRecordedSample,
            // Paneller User-Agent denetler; motor bu başlığı iletmek zorunda.
            headers: provider.streamHeaders
        )
    }

    // MARK: - Film

    public func playbackItem(for movie: Movie) async throws -> PlaybackItem {
        let context = try await providerContext(for: movie.playlistID)
        let provider = context.provider

        guard let url = provider.streamURL(for: movie) else {
            throw AppError.playbackFailed(reason: "Film adresi kurulamadı")
        }

        // Kaldığı yerden devam: bitmiş içerik baştan başlar.
        let source = PlaybackItem.Source.movie(movie.id)
        let stored = try? await progress.progress(for: source)
        let resumeAt = (stored?.isFinished == false) ? stored?.positionSeconds : nil
        try ensureSubscriptionIsAvailable(context.playlist)

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
        let context = try await providerContext(for: series.playlistID)
        let provider = context.provider

        guard let url = provider.streamURL(for: episode) else {
            throw AppError.playbackFailed(reason: "Bölüm adresi kurulamadı")
        }

        let source = PlaybackItem.Source.episode(episode.id)
        let stored = try? await progress.progress(for: source)
        let resumeAt = (stored?.isFinished == false) ? stored?.positionSeconds : nil
        try ensureSubscriptionIsAvailable(context.playlist)

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

    private func providerContext(for playlistID: Playlist.ID) async throws -> (provider: ContentProvider, playlist: Playlist) {
        guard let playlist = try await playlists.playlist(id: playlistID) else {
            // Kaynak silinmiş ama ekran hâlâ açık olabilir.
            throw AppError.notFound
        }
        try ensureSubscriptionIsAvailable(playlist)
        let provider = try await providerFactory.makeProvider(for: playlist)
        // DNS/sağlayıcı kurulumu beklerken gerçek bitiş anı geçmiş olabilir.
        try ensureSubscriptionIsAvailable(playlist)
        return (provider, playlist)
    }

    private func ensureSubscriptionIsAvailable(_ playlist: Playlist) throws {
        if let block = playlist.subscriptionBlock(at: now()) {
            throw AppError.subscriptionUnavailable(block)
        }
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
