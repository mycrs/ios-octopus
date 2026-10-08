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
    private var detailTasks: [Movie.ID: Task<Movie, Error>] = [:]

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
                // ⚠️ Sıra panelden: sağlayıcı listeyi kasıtlı diziyor
                // (yeni eklenenler, öne çıkarılanlar başta) ve alfabetik
                // sıralamak o bilgiyi siliyordu.
                //
                // ⚠️ `title` ikinci sırada: göç mevcut satırlara dokunmuyor,
                // hepsi `sortOrder = 0` ile geliyor. Bu sayede ilk
                // senkronizasyona kadar sıra eski alfabetik düzen olarak
                // kalıyor — kullanıcı arada bozulma görmüyor. Göçte veri
                // yazmak (FTS tetikleyicileri yüzünden) uygulamayı
                // açılamaz hâle getirmişti.
                //
                // ⚠️ `id` beraberlik bozucu — sıralamayı **kesin** yapar.
                // IPTV listelerinde aynı film birden çok kalitede geçiyor
                // ("Inception FHD", "Inception HD" değil, birebir aynı ad).
                // Beraberlik bozucu olmadan eşit sıraların düzeni belirsizdi
                // ve sayfa sınırında öğeler tekrar edip kaybolabiliyordu.
                .order(Column("sortOrder"), Column("title"), Column("id"))
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
        try Task.checkCancellation()
        if let running = detailTasks[id] {
            let result = try await running.value
            try Task.checkCancellation()
            return result
        }

        // Actor, await sırasında başka çağrıları kabul eder. Aynı filmin iki
        // ekranı önbellek dolmadan açılırsa tek ağ isteğini ve yazımı paylaşır.
        let task = Task { try await self.loadAndStoreDetails(id: id) }
        detailTasks[id] = task
        defer { detailTasks[id] = nil }
        let result = try await task.value
        try Task.checkCancellation()
        return result
    }

    private func loadAndStoreDetails(id: Movie.ID) async throws -> Movie {
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
        let enriched: Movie
        do {
            enriched = try await detailLoader.loadDetails(for: stored)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Log.network.info("Film künyesi alınamadı, liste verisiyle devam ediliyor")
            return stored
        }

        return try await database.write { db in
            // İstek beklenirken katalog yenilenmiş olabilir; güncel sıra,
            // kategori ve koruma bayrağını eski yanıtla ezme.
            guard let current = try MovieRecord.fetchOne(db, key: id.value) else {
                throw AppError.notFound
            }
            let merged = Self.merging(enriched, into: current.toDomain())
            try MovieRecord(merged, detailsLoadedAt: Date()).update(db)
            return merged
        }
    }

    private static func merging(_ details: Movie, into stored: Movie) -> Movie {
        var result = stored
        if !details.title.isEmpty { result.title = details.title }
        result.containerExtension = details.containerExtension ?? stored.containerExtension
        result.posterURL = details.posterURL ?? stored.posterURL
        result.backdropURL = details.backdropURL ?? stored.backdropURL
        result.plot = details.plot ?? stored.plot
        result.releaseDate = details.releaseDate ?? stored.releaseDate
        result.durationSeconds = details.durationSeconds ?? stored.durationSeconds
        result.rating = details.rating ?? stored.rating
        if !details.genres.isEmpty { result.genres = details.genres }
        if !details.cast.isEmpty { result.cast = details.cast }
        result.director = details.director ?? stored.director
        result.isAdult = stored.isAdult || details.isAdult
        return result
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
                    ORDER BY movie.sortOrder, movie.title, movie.id
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
    private var detailTasks: [Series.ID: Task<Void, Error>] = [:]

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
                // Panel sırası + beraberlik bozucu — film kataloğuyla
                // aynı gerekçe.
                .order(Column("sortOrder"), Column("title"), Column("id"))
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

    /// Son eklenen diziler.
    ///
    /// ⚠️ Filmlerdeki `addedAt` alanının dizi karşılığı **yok**; sıralama
    /// `lastModified` üzerinden (bkz. `SeriesRepository.recentlyAdded`).
    /// Alanı boş olan kayıtlar elenir, yoksa veri gelmeyen paneller rafı
    /// rastgele dizilerle doldururdu.
    public func recentlyAdded(playlistID: Playlist.ID, limit: Int) async throws -> [Series] {
        let records = try await database.read { db in
            try SeriesRecord
                .filter(Column("playlistId") == playlistID.value)
                .filter(Column("lastModified") != nil)
                .order(Column("lastModified").desc)
                .limit(limit)
                .fetchAll(db)
        }
        return records.map { $0.toDomain() }
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
        try Task.checkCancellation()
        if let running = detailTasks[id] {
            try await running.value
            try Task.checkCancellation()
            return
        }

        let task = Task { try await self.loadAndStoreDetails(id: id) }
        detailTasks[id] = task
        defer { detailTasks[id] = nil }
        try await task.value
        try Task.checkCancellation()
    }

    private func loadAndStoreDetails(id: Series.ID) async throws {
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
                    ORDER BY series.sortOrder, series.title, series.id
                    LIMIT ?
                    """,
                arguments: [pattern, playlistID.value, limit]
            )
        }
        return records.map { $0.toDomain() }
    }
}
