import Foundation
import GRDB
import OctopusCore
import OctopusDomain

// Film ve dizi depoları. Kalıp `GRDBChannelRepository` ile aynıdır:
// sorgu kurucu → Record → entity. Sıralama her yerde SABİT tutulur ki
// sayfalı yükleme sırasında liste kaymasın.

// MARK: - Filmler

/// Film künyesini uzak kaynaktan getirir.
public protocol MovieDetailLoading: Sendable {
    func loadDetails(for movie: Movie) async throws -> Movie
}

public actor GRDBVODRepository: VODRepository {

    private let database: AppDatabase
    private let detailLoader: MovieDetailLoading?

    public init(database: AppDatabase, detailLoader: MovieDetailLoading? = nil) {
        self.database = database
        self.detailLoader = detailLoader
    }

    public func categories(playlistID: Playlist.ID) async throws -> [MediaCategory] {
        let records = try await database.read { db in
            try CategoryRecord
                .filter(Column("playlistId") == playlistID.value)
                .filter(Column("kind") == MediaCategory.Kind.movie.rawValue)
                .order(Column("sortOrder"), Column("name"))
                .fetchAll(db)
        }
        return try records.map { try $0.toDomain() }
    }

    public func movies(
        playlistID: Playlist.ID,
        categoryID: MediaCategory.ID?,
        limit: Int,
        offset: Int
    ) async throws -> [Movie] {
        let records = try await database.read { db in
            var request = MovieRecord.filter(Column("playlistId") == playlistID.value)
            if let categoryID {
                request = request.filter(Column("categoryId") == categoryID.value)
            }
            return try request
                // ⚠️ `id` beraberlik bozucu — sıralamayı **kesin** yapar.
                // IPTV listelerinde aynı film birden çok kalitede geçiyor
                // ("Inception FHD", "Inception HD" değil, birebir aynı ad).
                // Yalnızca `title` ile sıralarken eşit başlıkların sırası
                // belirsizdi ve sayfa sınırında öğeler tekrar edip
                // kaybolabiliyordu.
                .order(Column("title"), Column("id"))
                .limit(limit, offset: offset)
                .fetchAll(db)
        }
        return records.map { $0.toDomain() }
    }

    public func movie(id: Movie.ID) async throws -> Movie? {
        let record = try await database.read { db in
            try MovieRecord.fetchOne(db, key: id.value)
        }
        return record?.toDomain()
    }

    /// Künyeyi getirir ve saklar.
    ///
    /// ⚠️ **Önbellekli**: `get_vod_info` her detay açılışında çağrılırsa
    /// kullanıcı her seferinde bekler. Bir kez çekilen künye yerelde tutulur.
    public func loadDetails(id: Movie.ID) async throws -> Movie {
        guard let record = try await database.read({ db in
            try MovieRecord.fetchOne(db, key: id.value)
        }) else {
            throw AppError.notFound
        }

        let stored = record.toDomain()
        if record.detailsLoadedAt != nil { return stored }
        guard let detailLoader else { return stored }

        // Detay ucu hata verirse liste verisiyle devam edilir; kullanıcı
        // en azından afiş ve adı görüp filmi oynatabilmeli.
        guard let enriched = try? await detailLoader.loadDetails(for: stored) else {
            Log.network.info("Film künyesi alınamadı, liste verisiyle devam ediliyor")
            return stored
        }

        try await database.write { db in
            try MovieRecord(enriched, detailsLoadedAt: Date()).update(db)
        }
        return enriched
    }

    public func search(
        query: String,
        playlistID: Playlist.ID,
        limit: Int
    ) async throws -> [Movie] {
        guard let pattern = FTS5Pattern(matchingAllPrefixesIn: query) else { return [] }
        let records = try await database.read { db in
            try MovieRecord.fetchAll(
                db,
                sql: """
                    SELECT movie.* FROM movie
                    JOIN movieSearch ON movieSearch.rowid = movie.rowid
                    WHERE movieSearch MATCH ? AND movie.playlistId = ?
                    ORDER BY movie.title
                    LIMIT ?
                    """,
                arguments: [pattern, playlistID.value, limit]
            )
        }
        return records.map { $0.toDomain() }
    }

    public func recentlyAdded(playlistID: Playlist.ID, limit: Int) async throws -> [Movie] {
        let records = try await database.read { db in
            try MovieRecord
                .filter(Column("playlistId") == playlistID.value)
                .filter(Column("addedAt") != nil)
                .order(Column("addedAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
        return records.map { $0.toDomain() }
    }
}

// MARK: - Diziler

/// Sezon/bölüm ağacını uzak kaynaktan getirir.
///
/// Depodan ayrı bir sözleşme: depo yerel veriden sorumlu, bu tip uzak
/// veriden. Böylece depo `ContentProvider`'ı tanımak zorunda kalmıyor.
public protocol SeriesDetailLoading: Sendable {
    func loadDetails(for series: Series) async throws -> (seasons: [Season], episodes: [Episode])
}

public actor GRDBSeriesRepository: SeriesRepository {

    private let database: AppDatabase
    private let detailLoader: SeriesDetailLoading?

    public init(database: AppDatabase, detailLoader: SeriesDetailLoading? = nil) {
        self.database = database
        self.detailLoader = detailLoader
    }

    public func categories(playlistID: Playlist.ID) async throws -> [MediaCategory] {
        let records = try await database.read { db in
            try CategoryRecord
                .filter(Column("playlistId") == playlistID.value)
                .filter(Column("kind") == MediaCategory.Kind.series.rawValue)
                .order(Column("sortOrder"), Column("name"))
                .fetchAll(db)
        }
        return try records.map { try $0.toDomain() }
    }

    public func series(
        playlistID: Playlist.ID,
        categoryID: MediaCategory.ID?,
        limit: Int,
        offset: Int
    ) async throws -> [Series] {
        let records = try await database.read { db in
            var request = SeriesRecord.filter(Column("playlistId") == playlistID.value)
            if let categoryID {
                request = request.filter(Column("categoryId") == categoryID.value)
            }
            return try request
                // Beraberlik bozucu — film kataloğuyla aynı gerekçe.
                .order(Column("title"), Column("id"))
                .limit(limit, offset: offset)
                .fetchAll(db)
        }
        return records.map { $0.toDomain() }
    }

    public func series(id: Series.ID) async throws -> Series? {
        let record = try await database.read { db in
            try SeriesRecord.fetchOne(db, key: id.value)
        }
        return record?.toDomain()
    }

    public func seasons(seriesID: Series.ID) async throws -> [Season] {
        let records = try await database.read { db in
            try SeasonRecord
                .filter(Column("seriesId") == seriesID.value)
                .order(Column("number"))
                .fetchAll(db)
        }
        return records.map { $0.toDomain() }
    }

    public func episodes(seriesID: Series.ID, seasonNumber: Int) async throws -> [Episode] {
        let records = try await database.read { db in
            try EpisodeRecord
                .filter(Column("seriesId") == seriesID.value)
                .filter(Column("seasonNumber") == seasonNumber)
                .order(Column("number"))
                .fetchAll(db)
        }
        return records.map { $0.toDomain() }
    }

    public func episode(id: Episode.ID) async throws -> Episode? {
        let record = try await database.read { db in
            try EpisodeRecord.fetchOne(db, key: id.value)
        }
        return record?.toDomain()
    }

    /// Sezon/bölüm ağacını getirir ve saklar.
    ///
    /// ⚠️ **Önbellekli**: referans projede `get_series_info` her dizi
    /// açılışında yeniden çağrılıyordu; ağır bir istek ve kullanıcı her
    /// seferinde bekliyordu. Bir kez çekilen ağaç yerelde tutulur.
    public func loadDetails(id: Series.ID) async throws {
        guard let record = try await database.read({ db in
            try SeriesRecord.fetchOne(db, key: id.value)
        }) else {
            throw AppError.notFound
        }

        // Daha önce çekildiyse tekrar istek atılmaz.
        if record.detailsLoadedAt != nil { return }
        guard let detailLoader else { return }

        let result = try await detailLoader.loadDetails(for: record.toDomain())

        try await database.write { db in
            // Ağaç tamamen değiştirilir: panelde bölüm eklenmiş/çıkarılmış olabilir.
            try SeasonRecord.filter(Column("seriesId") == id.value).deleteAll(db)
            try EpisodeRecord.filter(Column("seriesId") == id.value).deleteAll(db)

            for season in result.seasons {
                try SeasonRecord(season).insert(db)
            }
            for episode in result.episodes {
                try EpisodeRecord(episode).insert(db)
            }
            try db.execute(
                sql: "UPDATE series SET detailsLoadedAt = ? WHERE id = ?",
                arguments: [Date(), id.value]
            )
        }

        Log.sync.info("Dizi ağacı yüklendi: \(result.episodes.count) bölüm")
    }

    /// Kullanıcı "yenile" derse önbellek atlanır.
    public func invalidateDetails(id: Series.ID) async throws {
        try await database.write { db in
            try db.execute(
                sql: "UPDATE series SET detailsLoadedAt = NULL WHERE id = ?",
                arguments: [id.value]
            )
        }
    }

    public func search(
        query: String,
        playlistID: Playlist.ID,
        limit: Int
    ) async throws -> [Series] {
        guard let pattern = FTS5Pattern(matchingAllPrefixesIn: query) else { return [] }
        let records = try await database.read { db in
            try SeriesRecord.fetchAll(
                db,
                sql: """
                    SELECT series.* FROM series
                    JOIN seriesSearch ON seriesSearch.rowid = series.rowid
                    WHERE seriesSearch MATCH ? AND series.playlistId = ?
                    ORDER BY series.title
                    LIMIT ?
                    """,
                arguments: [pattern, playlistID.value, limit]
            )
        }
        return records.map { $0.toDomain() }
    }
}
