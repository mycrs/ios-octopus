import Foundation
import GRDB

// Veritabanı şeması ve göç (migration) zinciri.
//
// KURAL: Yayınlanmış bir migration ASLA değiştirilmez — yenisi eklenir.
// Kullanıcının cihazındaki veritabanı bu zinciri sırayla uygular.

extension AppDatabase {

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        // Geliştirme sırasında şema değişince veritabanını sıfırdan kur.
        // Yayına çıkmadan önce (Faz 11) kapatılacak.
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1_katalog") { db in
            try createSourceTables(db)
            try createCatalogTables(db)
            try createSeriesTables(db)
            try createEPGTable(db)
            try createUserDataTables(db)
        }

        migrator.registerMigration("v2_arama") { db in
            try createSearchIndexes(db)
        }

        return migrator
    }

    // MARK: - Kaynaklar

    private static func createSourceTables(_ db: Database) throws {
        try db.create(table: "playlist") { t in
            t.primaryKey("id", .text)
            t.column("name", .text).notNull()

            // Playlist.Kind ayrı kolonlara açılır — tek JSON blob olarak
            // saklansaydı "aktif Xtream kaynakları" gibi sorgular yazılamazdı.
            t.column("kindType", .text).notNull()
            t.column("host", .text)
            t.column("username", .text)
            t.column("url", .text)
            t.column("fileName", .text)
            t.column("activationCode", .text)

            t.column("epgURL", .text)
            t.column("createdAt", .datetime).notNull()
            t.column("lastSyncedAt", .datetime)
            t.column("isActive", .boolean).notNull().defaults(to: false)
        }

        try db.create(table: "category") { t in
            t.primaryKey("id", .text)
            t.column("playlistId", .text).notNull()
                .references("playlist", onDelete: .cascade)
            t.column("kind", .text).notNull()
            t.column("name", .text).notNull()
            t.column("sortOrder", .integer).notNull().defaults(to: 0)
        }
        try db.create(
            index: "category_byPlaylistKind",
            on: "category",
            columns: ["playlistId", "kind", "sortOrder"]
        )
    }

    // MARK: - Katalog
    //
    // ⚠️ TASARIM KARARI — kimlikler GLOBAL BENZERSİZ.
    // Sağlayıcıdan gelen ham id (Xtream'de `stream_id`) farklı kaynaklarda
    // çakışır: iki ayrı hesapta da "1234" numaralı kanal olabilir.
    // Bu yüzden Data katmanı kimliği `<playlistId>#<hamId>` biçiminde kurar
    // (bkz. EntityID). Ham değer `streamKey` kolonunda korunur.
    //
    // Kazanç: favori/ilerleme/geçmiş kayıtları tek anahtarla çalışır,
    // yanlış kaynağın kanalı favori görünmez.

    private static func createCatalogTables(_ db: Database) throws {
        try db.create(table: "channel") { t in
            t.primaryKey("id", .text)
            t.column("playlistId", .text).notNull()
                .references("playlist", onDelete: .cascade)
            t.column("name", .text).notNull()
            t.column("streamKey", .text).notNull()
            t.column("logoURL", .text)
            t.column("categoryId", .text)
            t.column("epgChannelId", .text)
            t.column("number", .integer)
            t.column("sortOrder", .integer).notNull().defaults(to: 0)
            t.column("isAdult", .boolean).notNull().defaults(to: false)
        }
        // Kanal listesi ekranının ana sorgusu.
        try db.create(
            index: "channel_byCategory",
            on: "channel",
            columns: ["playlistId", "categoryId", "sortOrder"]
        )
        // EPG eşleştirmesi bu kolon üzerinden yapılır.
        try db.create(index: "channel_byEpgId", on: "channel", columns: ["epgChannelId"])

        try db.create(table: "movie") { t in
            t.primaryKey("id", .text)
            t.column("playlistId", .text).notNull()
                .references("playlist", onDelete: .cascade)
            t.column("title", .text).notNull()
            t.column("streamKey", .text).notNull()
            t.column("containerExtension", .text)
            t.column("posterURL", .text)
            t.column("backdropURL", .text)
            t.column("categoryId", .text)
            t.column("plot", .text)
            t.column("releaseDate", .datetime)
            t.column("durationSeconds", .integer)
            t.column("rating", .double)
            // Diziler halinde saklanır (JSON) — bu alanlarda sorgu yapılmıyor.
            t.column("genres", .text).notNull().defaults(to: "[]")
            t.column("cast", .text).notNull().defaults(to: "[]")
            t.column("director", .text)
            t.column("isAdult", .boolean).notNull().defaults(to: false)
            t.column("addedAt", .datetime)
            // Detay (özet, oyuncular) sonradan çekilir; tekrar çekmemek için işaret.
            t.column("detailsLoadedAt", .datetime)
        }
        try db.create(
            index: "movie_byCategory",
            on: "movie",
            columns: ["playlistId", "categoryId", "title"]
        )
        // "Son eklenenler" rafı.
        try db.create(index: "movie_byAdded", on: "movie", columns: ["playlistId", "addedAt"])
    }

    // MARK: - Diziler

    private static func createSeriesTables(_ db: Database) throws {
        try db.create(table: "series") { t in
            t.primaryKey("id", .text)
            t.column("playlistId", .text).notNull()
                .references("playlist", onDelete: .cascade)
            t.column("title", .text).notNull()
            t.column("streamKey", .text).notNull()
            t.column("posterURL", .text)
            t.column("backdropURL", .text)
            t.column("categoryId", .text)
            t.column("plot", .text)
            t.column("rating", .double)
            t.column("genres", .text).notNull().defaults(to: "[]")
            t.column("cast", .text).notNull().defaults(to: "[]")
            t.column("releaseDate", .datetime)
            t.column("lastModified", .datetime)
            t.column("detailsLoadedAt", .datetime)
        }
        try db.create(
            index: "series_byCategory",
            on: "series",
            columns: ["playlistId", "categoryId", "title"]
        )

        try db.create(table: "season") { t in
            t.primaryKey("id", .text)
            t.column("seriesId", .text).notNull()
                .references("series", onDelete: .cascade)
            t.column("number", .integer).notNull()
            t.column("name", .text)
            t.column("posterURL", .text)
            t.column("episodeCount", .integer).notNull().defaults(to: 0)
        }
        try db.create(index: "season_bySeries", on: "season", columns: ["seriesId", "number"])

        try db.create(table: "episode") { t in
            t.primaryKey("id", .text)
            t.column("seriesId", .text).notNull()
                .references("series", onDelete: .cascade)
            t.column("seasonNumber", .integer).notNull()
            t.column("number", .integer).notNull()
            t.column("title", .text).notNull()
            t.column("streamKey", .text).notNull()
            t.column("containerExtension", .text)
            t.column("plot", .text)
            t.column("stillURL", .text)
            t.column("durationSeconds", .integer)
            t.column("airDate", .datetime)
        }
        try db.create(
            index: "episode_bySeason",
            on: "episode",
            columns: ["seriesId", "seasonNumber", "number"]
        )
    }

    // MARK: - EPG

    private static func createEPGTable(_ db: Database) throws {
        try db.create(table: "epgProgram") { t in
            t.primaryKey("id", .text)
            // Kanala yabancı anahtar YOK: XMLTV, uygulamada bulunmayan
            // kanallar için de program taşır. Eşleştirme `epgChannelId` ile yapılır.
            t.column("epgChannelId", .text).notNull()
            t.column("title", .text).notNull()
            t.column("summary", .text)
            t.column("startDate", .datetime).notNull()
            t.column("endDate", .datetime).notNull()
        }
        // "Şu an ne oynuyor" ve rehber ızgarası sorgusu.
        try db.create(
            index: "epg_byChannelTime",
            on: "epgProgram",
            columns: ["epgChannelId", "startDate", "endDate"]
        )
        // Geçmiş kayıtların temizliği (purgePrograms).
        try db.create(index: "epg_byEnd", on: "epgProgram", columns: ["endDate"])
    }

    // MARK: - Kullanıcı verileri
    //
    // Bu tablolarda `playlistId` yok ve yabancı anahtar da yok:
    // kaynak silinip yeniden eklendiğinde favoriler ve izleme ilerlemesi
    // kaybolmasın diye. Kimlikler global benzersiz olduğu için eşleşme korunur.

    private static func createUserDataTables(_ db: Database) throws {
        try db.create(table: "favorite") { t in
            t.primaryKey("itemKey", .text)
            t.column("addedAt", .datetime).notNull()
        }

        try db.create(table: "playbackProgress") { t in
            t.primaryKey("itemKey", .text)
            t.column("positionSeconds", .double).notNull()
            t.column("durationSeconds", .double).notNull()
            t.column("updatedAt", .datetime).notNull()
        }
        // "İzlemeye devam et" rafı en son güncellenene göre sıralar.
        try db.create(
            index: "progress_byUpdated",
            on: "playbackProgress",
            columns: ["updatedAt"]
        )

        try db.create(table: "watchHistory") { t in
            t.primaryKey("itemKey", .text)
            t.column("playedAt", .datetime).notNull()
        }
        try db.create(index: "history_byPlayed", on: "watchHistory", columns: ["playedAt"])
    }

    // MARK: - Tam metin arama
    //
    // FTS5 sanal tabloları kaynak tabloyla otomatik eşitlenir
    // (`synchronize` gerekli trigger'ları kurar) — elle güncelleme yok.

    private static func createSearchIndexes(_ db: Database) throws {
        try db.create(virtualTable: "channelSearch", using: FTS5()) { t in
            t.synchronize(withTable: "channel")
            t.column("name")
            t.tokenizer = .unicode61()
        }

        try db.create(virtualTable: "movieSearch", using: FTS5()) { t in
            t.synchronize(withTable: "movie")
            t.column("title")
            t.tokenizer = .unicode61()
        }

        try db.create(virtualTable: "seriesSearch", using: FTS5()) { t in
            t.synchronize(withTable: "series")
            t.column("title")
            t.tokenizer = .unicode61()
        }
    }
}
