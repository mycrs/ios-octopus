import Foundation
import GRDB
import OctopusCore
import OctopusDomain

/// Senkronizasyon sonucunu veritabanına yazar.
///
/// ## Neden "değiştir" (replace) stratejisi?
/// Sağlayıcıdan gelen liste **tam listedir**. Yalnızca ekleme yapılsaydı
/// sağlayıcıda kaldırılan kanallar cihazda sonsuza kadar kalır ve
/// tıklandığında "yayın yok" hatası verirdi.
///
/// Silme + yazma **tek işlemde** yapılır: yarıda kalırsa katalog boş kalmaz,
/// ekranı besleyen gözlem de yalnızca işlem bitince tetiklenir (liste
/// bir an boş görünmez).
///
/// ⚠️ Favoriler, izleme ilerlemesi ve geçmiş bu işlemden **etkilenmez** —
/// ayrı tablolarda ve yabancı anahtarsız tutulurlar.
struct CatalogWriter {

    let database: AppDatabase

    /// Canlı yayın kataloğunu değiştirir.
    func replaceLiveCatalog(
        playlistID: Playlist.ID,
        categories: [MediaCategory],
        channels: [Channel]
    ) async throws {
        try await database.write { db in
            try deleteCategories(db, playlistID: playlistID, kind: .live)
            try ChannelRecord
                .filter(Column("playlistId") == playlistID.value)
                .deleteAll(db)

            for category in categories {
                try CategoryRecord(category).insert(db)
            }
            // Satır satır yazılır. Referans projede katalog TEK satıra
            // yazıldığı için 14k kanalda ~2MB'lık satır SQLite cursor
            // penceresini taşırmış ve önbellek sessizce hiç çalışmamıştı.
            for channel in channels {
                try ChannelRecord(channel).insert(db)
            }
        }
        Log.sync.info("Canlı katalog yazıldı: \(channels.count) kanal, \(categories.count) kategori")
    }

    func replaceMovieCatalog(
        playlistID: Playlist.ID,
        categories: [MediaCategory],
        movies: [Movie]
    ) async throws {
        try await database.write { db in
            try deleteCategories(db, playlistID: playlistID, kind: .movie)
            try MovieRecord
                .filter(Column("playlistId") == playlistID.value)
                .deleteAll(db)

            for category in categories {
                try CategoryRecord(category).insert(db)
            }
            for movie in movies {
                try MovieRecord(movie).insert(db)
            }
        }
        Log.sync.info("Film kataloğu yazıldı: \(movies.count) film")
    }

    func replaceSeriesCatalog(
        playlistID: Playlist.ID,
        categories: [MediaCategory],
        series: [Series]
    ) async throws {
        try await database.write { db in
            try deleteCategories(db, playlistID: playlistID, kind: .series)
            // Sezon ve bölümler dizilere cascade ile bağlı; ayrıca silinmez.
            try SeriesRecord
                .filter(Column("playlistId") == playlistID.value)
                .deleteAll(db)

            for category in categories {
                try CategoryRecord(category).insert(db)
            }
            for item in series {
                try SeriesRecord(item).insert(db)
            }
        }
        Log.sync.info("Dizi kataloğu yazıldı: \(series.count) dizi")
    }

    /// EPG programlarını parça parça yazar.
    ///
    /// XMLTV çözümleyici parçalar hâlinde teslim eder; her parça kendi
    /// işleminde yazılır ki büyük rehberlerde bellek şişmesin.
    func appendEPGChunk(_ programs: [EPGProgram]) async throws {
        guard !programs.isEmpty else { return }
        try await database.write { db in
            for program in programs {
                // Aynı rehber tekrar çekildiğinde kopya oluşmaz:
                // kimlik kanal + başlangıç zamanından türetiliyor.
                try EPGProgramRecord(program).save(db)
            }
        }
    }

    func markSynced(playlistID: Playlist.ID, at date: Date) async throws {
        try await database.write { db in
            try db.execute(
                sql: "UPDATE playlist SET lastSyncedAt = ? WHERE id = ?",
                arguments: [date, playlistID.value]
            )
        }
    }

    private func deleteCategories(
        _ db: Database,
        playlistID: Playlist.ID,
        kind: MediaCategory.Kind
    ) throws {
        try CategoryRecord
            .filter(Column("playlistId") == playlistID.value)
            .filter(Column("kind") == kind.rawValue)
            .deleteAll(db)
    }
}
