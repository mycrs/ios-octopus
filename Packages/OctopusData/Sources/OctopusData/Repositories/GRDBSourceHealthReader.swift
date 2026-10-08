import Foundation
import GRDB
import OctopusDomain

/// Tek tutarlı okuma içinde toplama sorguları; büyük katalogları belleğe taşımaz.
public struct GRDBSourceHealthReader: SourceHealthReading {
    private let database: AppDatabase

    public init(database: AppDatabase) { self.database = database }

    public func snapshot(playlistID: Playlist.ID, at date: Date) async throws -> SourceHealthSnapshot {
        try Task.checkCancellation()
        let result: SourceHealthSnapshot? = try await database.read { db in
            guard let source = try PlaylistRecord.fetchOne(db, key: playlistID.value) else {
                return nil
            }
            guard let storedKind = PlaylistRecord.KindType(rawValue: source.kindType) else {
                throw AppError.storage(reason: "Bilinmeyen kaynak türü")
            }
            let kind: SourceHealthSnapshot.SourceKind
            switch storedKind {
            case .xtream: kind = .xtream
            case .m3u: kind = .m3u
            case .m3uLocalFile: kind = .localFile
            case .activationCode: kind = .activation
            }
            let arguments: StatementArguments = [playlistID.value]
            let row = try Row.fetchOne(db, sql: Self.summarySQL, arguments: arguments)
            guard let row else { throw AppError.storage(reason: "Katalog özeti okunamadı") }
            return SourceHealthSnapshot(
                sourceKind: kind, checkedAt: date, lastSyncedAt: source.lastSyncedAt,
                accountExpired: source.expiresAt.map { $0 <= date } ?? false,
                channels: row["channels"], movies: row["movies"], series: row["series"],
                categories: row["categories"], duplicateChannels: row["duplicates"],
                channelsWithoutGuide: row["withoutGuide"], channelsWithoutArtwork: row["withoutArtwork"]
            )
        }
        try Task.checkCancellation()
        guard let result else { throw AppError.notFound }
        return result
    }

    static let summarySQL = """
        WITH source AS (SELECT ? AS id),
        selectedChannels AS (
            SELECT streamKey, epgChannelId, logoURL FROM channel
            WHERE playlistId = (SELECT id FROM source)
        )
        SELECT
            (SELECT COUNT(*) FROM selectedChannels) AS channels,
            (SELECT COUNT(*) FROM movie WHERE playlistId = (SELECT id FROM source)) AS movies,
            (SELECT COUNT(*) FROM series WHERE playlistId = (SELECT id FROM source)) AS series,
            (SELECT COUNT(*) FROM category WHERE playlistId = (SELECT id FROM source)) AS categories,
            (SELECT COALESCE(SUM(copies - 1), 0) FROM (
                SELECT COUNT(*) AS copies FROM selectedChannels
                WHERE TRIM(streamKey) <> '' GROUP BY TRIM(streamKey) HAVING COUNT(*) > 1
            )) AS duplicates,
            (SELECT COUNT(*) FROM selectedChannels WHERE TRIM(COALESCE(epgChannelId, '')) = '') AS withoutGuide,
            (SELECT COUNT(*) FROM selectedChannels WHERE TRIM(COALESCE(logoURL, '')) = '') AS withoutArtwork
        """
}
