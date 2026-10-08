import Foundation

/// Yerel katalog kontrolü. Uzak sunucuya veya yayınlara istek göndermez.
public protocol SourceHealthReading: Sendable {
    func snapshot(playlistID: Playlist.ID, at date: Date) async throws -> SourceHealthSnapshot
}

/// Rapor paylaşılırken sırları yanlışlıkla taşımamak için URL/entity içermez.
public struct SourceHealthSnapshot: Codable, Equatable, Sendable {
    public enum SourceKind: String, Codable, Sendable {
        case xtream, m3u, localFile, activation
    }

    public let sourceKind: SourceKind
    public let checkedAt: Date
    public let lastSyncedAt: Date?
    public let accountExpired: Bool
    public let channels: Int
    public let movies: Int
    public let series: Int
    public let categories: Int
    /// Aynı yayın anahtarının ilk kaydı dışındaki ek kayıtların sayısı.
    public let duplicateChannels: Int
    public let channelsWithoutGuide: Int
    public let channelsWithoutArtwork: Int

    public init(
        sourceKind: SourceKind, checkedAt: Date, lastSyncedAt: Date?, accountExpired: Bool,
        channels: Int, movies: Int, series: Int, categories: Int,
        duplicateChannels: Int, channelsWithoutGuide: Int, channelsWithoutArtwork: Int
    ) {
        self.sourceKind = sourceKind
        self.checkedAt = checkedAt
        self.lastSyncedAt = lastSyncedAt
        self.accountExpired = accountExpired
        self.channels = channels
        self.movies = movies
        self.series = series
        self.categories = categories
        self.duplicateChannels = duplicateChannels
        self.channelsWithoutGuide = channelsWithoutGuide
        self.channelsWithoutArtwork = channelsWithoutArtwork
    }
}
