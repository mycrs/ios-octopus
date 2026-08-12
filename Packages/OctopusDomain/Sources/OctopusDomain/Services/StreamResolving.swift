import Foundation

/// İçerikten oynatılabilir akışa geçiş.
///
/// Akış URL'si kaynağa göre tamamen farklı kurulur:
/// - Xtream: `http://host:port/live/user/pass/{stream_id}.m3u8`
/// - M3U:    satırdaki URL doğrudan kullanılır
///
/// Bu farkı **yalnızca** Data katmanı bilir. Feature'lar bu protokolü çağırır,
/// elde ettikleri `PlaybackItem`'ı oynatıcıya verir. Başka bir şey bilmezler.
public protocol StreamResolving: Sendable {
    func playbackItem(for channel: Channel) async throws -> PlaybackItem
    func playbackItem(for movie: Movie) async throws -> PlaybackItem
    func playbackItem(for episode: Episode, in series: Series) async throws -> PlaybackItem
}

/// İlk kurulum sonunda kullanıcıya gösterilen gerçek katalog adetleri.
/// `nil`, ilgili kataloğun sunucu tarafından sağlanamadığını ifade eder;
/// boş ama başarıyla alınmış katalog ise `0` olarak taşınır.
public struct SyncContentCounts: Hashable, Sendable {
    public var channels: Int?
    public var movies: Int?
    public var series: Int?

    public init(channels: Int? = nil, movies: Int? = nil, series: Int? = nil) {
        self.channels = channels
        self.movies = movies
        self.series = series
    }

    public static let empty = SyncContentCounts()
}

/// Senkronizasyonun hangi aşamada olduğu — onboarding ekranı bunu gösterir.
public enum SyncStage: Hashable, Sendable {
    case idle
    case authenticating
    case fetchingCategories
    /// `total` bilinmiyorsa nil (M3U akış halinde parse edilir).
    case fetchingChannels(done: Int, total: Int?)
    case fetchingMovies(done: Int, total: Int?)
    case fetchingSeries(done: Int, total: Int?)
    case fetchingEPG
    case persisting
    case finished(at: Date, counts: SyncContentCounts = .empty)
    case failed(AppError)

    /// 0...1 arası kaba ilerleme — belirsizse nil (spinner gösterilir).
    public var fraction: Double? {
        switch self {
        case .idle: return 0
        case .authenticating: return 0.05
        case .fetchingCategories: return 0.10
        case .fetchingChannels(let done, let total):
            return Self.interpolate(done, total, from: 0.15, to: 0.45)
        case .fetchingMovies(let done, let total):
            return Self.interpolate(done, total, from: 0.45, to: 0.70)
        case .fetchingSeries(let done, let total):
            return Self.interpolate(done, total, from: 0.70, to: 0.85)
        case .fetchingEPG: return 0.90
        case .persisting: return 0.95
        case .finished: return 1
        case .failed: return nil
        }
    }

    public var isTerminal: Bool {
        switch self {
        case .finished, .failed: return true
        default: return false
        }
    }

    private static func interpolate(
        _ done: Int,
        _ total: Int?,
        from lower: Double,
        to upper: Double
    ) -> Double? {
        guard let total, total > 0 else { return nil }
        let ratio = min(max(Double(done) / Double(total), 0), 1)
        return lower + (upper - lower) * ratio
    }
}

/// Kaynağı yerel veritabanıyla eşitler.
public protocol ContentSyncing: Sendable {
    /// Tam senkronizasyon. Uzun sürer; iptal edilebilir olmalıdır.
    func sync(playlistID: Playlist.ID) async throws

    /// Yalnızca EPG'yi tazeler (ucuz, sık çağrılabilir).
    func syncEPG(playlistID: Playlist.ID) async throws

    /// İlerleme akışı — onboarding ve ayarlar ekranı dinler.
    func observeProgress(playlistID: Playlist.ID) -> AsyncStream<SyncStage>
}
