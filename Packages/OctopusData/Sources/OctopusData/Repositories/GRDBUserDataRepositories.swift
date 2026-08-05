import Foundation
import GRDB
import OctopusCore
import OctopusDomain

// MARK: - EPG

public actor GRDBEPGRepository: EPGRepository {

    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func nowPlaying(epgChannelID: String, at date: Date) async throws -> EPGProgram? {
        let record = try await database.read { db in
            try EPGProgramRecord
                .filter(Column("epgChannelId") == epgChannelID)
                .filter(Column("startDate") <= date && Column("endDate") > date)
                .fetchOne(db)
        }
        return record?.toDomain()
    }

    /// Toplu sorgu.
    ///
    /// Kanal listesinde her satır için ayrı sorgu atılsaydı 500 kanallık
    /// ekranda 500 sorgu olurdu (N+1). Tek `IN` sorgusuyla çözülür.
    public func nowPlaying(
        epgChannelIDs: [String],
        at date: Date
    ) async throws -> [String: EPGProgram] {
        guard !epgChannelIDs.isEmpty else { return [:] }

        let records = try await database.read { db in
            try EPGProgramRecord
                .filter(epgChannelIDs.contains(Column("epgChannelId")))
                .filter(Column("startDate") <= date && Column("endDate") > date)
                .fetchAll(db)
        }

        return Dictionary(
            records.map { ($0.epgChannelId, $0.toDomain()) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Tek sorguda tüm kanalların o anki programı.
    ///
    /// `epg_byChannelTime` indeksi zaman aralığını da kapsadığı için
    /// bu sorgu tam tarama yapmaz.
    public func allNowPlaying(at date: Date) async throws -> [String: EPGProgram] {
        let records = try await database.read { db in
            try EPGProgramRecord
                .filter(Column("startDate") <= date && Column("endDate") > date)
                .fetchAll(db)
        }
        return Dictionary(
            records.map { ($0.epgChannelId, $0.toDomain()) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    public func programs(
        epgChannelID: String,
        from: Date,
        to: Date
    ) async throws -> [EPGProgram] {
        let records = try await database.read { db in
            try EPGProgramRecord
                .filter(Column("epgChannelId") == epgChannelID)
                .filter(Column("endDate") > from && Column("startDate") < to)
                .order(Column("startDate"))
                .fetchAll(db)
        }
        return records.map { $0.toDomain() }
    }

    /// Süresi geçmiş kayıtları siler — EPG tablosu sınırsız büyümemeli.
    public func purgePrograms(before date: Date) async throws {
        let deleted = try await database.write { db in
            try EPGProgramRecord
                .filter(Column("endDate") < date)
                .deleteAll(db)
        }
        if deleted > 0 {
            Log.database.info("EPG temizliği: \(deleted) eski kayıt silindi")
        }
    }
}

// MARK: - Favoriler

public actor GRDBFavoritesRepository: FavoritesRepository {

    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func isFavorite(_ source: PlaybackItem.Source) async throws -> Bool {
        let key = source.storageKey
        return try await database.read { db in
            try FavoriteRecord.filter(Column("itemKey") == key).fetchCount(db) > 0
        }
    }

    /// - Returns: İşlem sonrası favori durumu.
    public func toggle(_ source: PlaybackItem.Source) async throws -> Bool {
        let key = source.storageKey
        return try await database.write { db -> Bool in
            if try FavoriteRecord.filter(Column("itemKey") == key).fetchCount(db) > 0 {
                _ = try FavoriteRecord.deleteOne(db, key: key)
                return false
            }
            try FavoriteRecord(itemKey: key, addedAt: Date()).insert(db)
            return true
        }
    }

    // Favori satırları yalnızca anahtar taşır; içerik tablolarıyla anahtar
    // birleştirilerek eşlenir. Sıralama favoriye ekleme zamanına göredir.

    public func favoriteChannels(playlistID: Playlist.ID) async throws -> [Channel] {
        let records = try await database.read { db in
            try ChannelRecord.fetchAll(
                db,
                sql: """
                    SELECT channel.* FROM channel
                    JOIN favorite ON favorite.itemKey = 'live:' || channel.id
                    WHERE channel.playlistId = ?
                    ORDER BY favorite.addedAt DESC
                    """,
                arguments: [playlistID.value]
            )
        }
        return records.map { $0.toDomain() }
    }

    public func favoriteMovies(playlistID: Playlist.ID) async throws -> [Movie] {
        let records = try await database.read { db in
            try MovieRecord.fetchAll(
                db,
                sql: """
                    SELECT movie.* FROM movie
                    JOIN favorite ON favorite.itemKey = 'movie:' || movie.id
                    WHERE movie.playlistId = ?
                    ORDER BY favorite.addedAt DESC
                    """,
                arguments: [playlistID.value]
            )
        }
        return records.map { $0.toDomain() }
    }

    public func favoriteSeries(playlistID: Playlist.ID) async throws -> [Series] {
        // Dizi favorileri bölüm anahtarıyla değil dizi anahtarıyla tutulur.
        let records = try await database.read { db in
            try SeriesRecord.fetchAll(
                db,
                sql: """
                    SELECT series.* FROM series
                    JOIN favorite ON favorite.itemKey = 'series:' || series.id
                    WHERE series.playlistId = ?
                    ORDER BY favorite.addedAt DESC
                    """,
                arguments: [playlistID.value]
            )
        }
        return records.map { $0.toDomain() }
    }

    /// Kalp ikonunun anında güncellenmesi için.
    public nonisolated func observeFavoriteKeys() -> AsyncStream<Set<String>> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { db in
                try String.fetchSet(db, sql: "SELECT itemKey FROM favorite")
            }
            let task = Task {
                do {
                    for try await keys in observation.values(in: database.writer) {
                        continuation.yield(keys)
                    }
                } catch {
                    Log.database.error("Favori gözlemi durdu: \(String(describing: error))")
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - İzleme ilerlemesi

public actor GRDBPlaybackProgressRepository: PlaybackProgressRepository {

    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func progress(for source: PlaybackItem.Source) async throws -> PlaybackProgress? {
        let key = source.storageKey
        let record = try await database.read { db in
            try PlaybackProgressRecord.fetchOne(db, key: key)
        }
        return record?.toDomain()
    }

    /// Oynatma sırasında periyodik çağrılır — var olan kaydın üzerine yazar.
    public func save(
        _ progress: PlaybackProgress,
        for source: PlaybackItem.Source
    ) async throws {
        // Anahtar her zaman kaynaktan türetilir: çağıran yanlış anahtar
        // gönderse bile kayıt doğru içeriğe bağlanır.
        let record = PlaybackProgressRecord(
            PlaybackProgress(
                itemKey: source.storageKey,
                positionSeconds: progress.positionSeconds,
                durationSeconds: progress.durationSeconds,
                updatedAt: progress.updatedAt
            )
        )
        try await database.write { db in
            try record.save(db)
        }
    }

    /// "İzlemeye devam et" rafı.
    ///
    /// Bitmiş (>%95) kayıtlar hariç tutulur. Kaynak filtresi anahtarın
    /// içindeki kaynak kimliğine bakar (bkz. EntityID).
    public func continueWatching(
        playlistID: Playlist.ID,
        limit: Int
    ) async throws -> [PlaybackProgress] {
        let records = try await database.read { db in
            try PlaybackProgressRecord.fetchAll(
                db,
                sql: """
                    SELECT * FROM playbackProgress
                    WHERE durationSeconds > 0
                      AND positionSeconds / durationSeconds < 0.95
                      AND itemKey LIKE '%:' || ? || '#%'
                    ORDER BY updatedAt DESC
                    LIMIT ?
                    """,
                arguments: [playlistID.value, limit]
            )
        }
        return records.map { $0.toDomain() }
    }

    public func clear(for source: PlaybackItem.Source) async throws {
        let key = source.storageKey
        try await database.write { db in
            _ = try PlaybackProgressRecord.deleteOne(db, key: key)
        }
    }

    public func clearAll() async throws {
        try await database.write { db in
            _ = try PlaybackProgressRecord.deleteAll(db)
        }
    }
}

// MARK: - İzleme geçmişi

public actor GRDBWatchHistoryRepository: WatchHistoryRepository {

    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func record(_ source: PlaybackItem.Source, at date: Date) async throws {
        let entry = WatchHistoryRecord(itemKey: source.storageKey, playedAt: date)
        try await database.write { db in
            // Aynı içerik tekrar izlenince yeni satır değil, zaman güncellenir.
            try entry.save(db)
        }
    }

    public func recentChannels(playlistID: Playlist.ID, limit: Int) async throws -> [Channel] {
        let records = try await database.read { db in
            try ChannelRecord.fetchAll(
                db,
                sql: """
                    SELECT channel.* FROM channel
                    JOIN watchHistory ON watchHistory.itemKey = 'live:' || channel.id
                    WHERE channel.playlistId = ?
                    ORDER BY watchHistory.playedAt DESC
                    LIMIT ?
                    """,
                arguments: [playlistID.value, limit]
            )
        }
        return records.map { $0.toDomain() }
    }

    public func clearAll() async throws {
        try await database.write { db in
            _ = try WatchHistoryRecord.deleteAll(db)
        }
    }
}
