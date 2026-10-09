import Foundation
import GRDB

// Veritabanı şeması ve göç (migration) zinciri.
//
// KURAL: Yayınlanmış bir migration ASLA değiştirilmez — yenisi eklenir.
// Kullanıcının cihazındaki veritabanı bu zinciri sırayla uygular.

extension AppDatabase {

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        // ⚠️ `eraseDatabaseOnSchemaChange` **kapalı** — kasıtlı.
        //
        // Açıkken (DEBUG) yeni bir migration eklemek veritabanını silip
        // sıfırdan kuruyordu. İki zararı vardı:
        //
        // 1. Gerçek cihazda katalog uçuyordu. 20 binlik bir listede
        //    yeniden kurulum uzun sürüyor ve uygulama o sırada boş ekranda
        //    kalıyor — "açılmıyor" diye görünen şey buydu.
        // 2. Daha önemlisi: **asıl göç yolu hiç denenmiyordu.** Kullanıcının
        //    cihazında çalışacak kod `ALTER TABLE` + veri taşıma; erase
        //    açıkken geliştirici bunun yerine hep temiz kurulumu görüyor.
        //    Yayına, bir kez bile çalıştırılmamış bir göçle çıkılıyordu.
        //
        // Bedeli: yayınlanmış bir migration'ı değiştirirsen şema uyuşmaz ve
        // hata alırsın. Zaten yukarıdaki kural bunu yasaklıyor — yenisini ekle.

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

        // Abonelik bitişi: `authenticate()` her senkronizasyonda zaten
        // çağrılıyordu ama sonucu atılıyordu. Ana sayfadaki hero "kaç gün
        // kaldı" bilgisini buradan okuyor.
        //
        // ⚠️ Ayrı migration: kolon `v1_katalog`'a eklenseydi mevcut
        // kurulumlarda tablo hiç güncellenmezdi (v1 zaten uygulanmış sayılır).
        migrator.registerMigration("v3_abonelik") { db in
            try db.alter(table: "playlist") { t in
                t.add(column: "expiresAt", .datetime)
            }
        }

        // Katalog sırası: panel ne sırayla veriyorsa o.
        //
        // ⚠️ Film ve diziler `title` ile sıralanıyordu. Sağlayıcı listeyi
        // kasıtlı diziyor (yeni eklenenler, öne çıkarılanlar başta) ve
        // alfabetik sıralamak o bilgiyi siliyordu; kullanıcının panelde
        // gördüğü sırayla da uyuşmuyordu. Kanallarda `sortOrder` baştan
        // vardı, VOD tarafında eksik kalmış.
        migrator.registerMigration("v4_panel_sirasi") { db in
            for table in ["movie", "series"] {
                try db.alter(table: table) { t in
                    t.add(column: "sortOrder", .integer).notNull().defaults(to: 0)
                }
            }

            // ⚠️ Mevcut satırlara **dokunulmuyor** — kasıtlı ve önemli.
            //
            // Önce burada bir `UPDATE` ile eski alfabetik düzen sortOrder'a
            // yazılıyordu. Gerçek cihazda uygulama açılmaz oldu: `movie`
            // üstünde FTS arama tetikleyicisi var ve her güncellenen satır
            // için arama indeksinden kaydı silip yeniden yazıyor. 16.898
            // filme dokunmak 16.898 indeks yeniden yazımı demekti; açılış
            // watchdog'u uygulamayı SIGKILL ile öldürüyordu.
            //
            // Gerek de yok: sıralama `sortOrder, title, id`. Senkronizasyon
            // öncesi tüm değerler 0 olduğu için sıra kendiliğinden eski
            // alfabetik düzen oluyor, ilk tazelemede panel sırasına geçiyor.
            // Aynı sonuç, tek satır veri yazmadan.
            try db.create(
                index: "movie_byCategoryOrder",
                on: "movie",
                columns: ["playlistId", "categoryId", "sortOrder", "title", "id"]
            )
            try db.create(
                index: "movie_byPlaylistOrder",
                on: "movie",
                columns: ["playlistId", "sortOrder", "title", "id"]
            )
            try db.create(
                index: "series_byCategoryOrder",
                on: "series",
                columns: ["playlistId", "categoryId", "sortOrder", "title", "id"]
            )
            try db.create(
                index: "series_byPlaylistOrder",
                on: "series",
                columns: ["playlistId", "sortOrder", "title", "id"]
            )
        }

        // XMLTV kanal/program kimlikleri sağlayıcılar arasında benzersiz
        // değildir. Eski kayıtların kaynağı bilinmediği için toplu eşleme
        // yapılmaz; nullable kolon onları korur, yeni rehber kaynakla yazılır.
        migrator.registerMigration("v5_epg_kaynak") { db in
            try db.alter(table: "epgProgram") { t in
                t.add(column: "playlistId", .text)
                    .references("playlist", onDelete: .cascade)
            }
            try db.create(
                index: "epg_byPlaylistChannelTime",
                on: "epgProgram",
                columns: ["playlistId", "epgChannelId", "startDate", "endDate"]
            )
            try db.create(
                index: "epg_byPlaylistEnd",
                on: "epgProgram",
                columns: ["playlistId", "endDate"]
            )
        }

        // Mevcut bölüm ağacı korunur; doğrudan adresi ilk ayrıntı yenilemesi doldurur.
        migrator.registerMigration("v6_bolum_dogrudan_adres") { db in
            try db.alter(table: "episode") { t in
                t.add(column: "directURL", .text)
            }
        }

        // Eski hesaplar bilinmeyen durumda kalır; katalog veya kullanıcı verisi yeniden yazılmaz.
        migrator.registerMigration("v7_abonelik_erisim") { db in
            try db.alter(table: "playlist") { t in
                t.add(column: "subscriptionStatus", .text)
            }
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
        // Kanal listesi ekranının ana sorgusu — kategori seçiliyken.
        //
        // ⚠️ `name` de indekste: sıralama `sortOrder, name`. Son kolon
        // eksik olsaydı SQLite indeksle süzüp sonra ayrıca sıralardı.
        try db.create(
            index: "channel_byCategory",
            on: "channel",
            columns: ["playlistId", "categoryId", "sortOrder", "name"]
        )
        // ⚠️ "Tümü" görünümü — **varsayılan ve en çok kullanılan** sorgu.
        // Yukarıdaki indeks bunu karşılamıyor: `categoryId` süzülmediğinde
        // ürettiği sıra (categoryId, sortOrder) oluyor, istenen ise
        // (sortOrder, name). 20.000 kanallı bir hesapta senkronizasyonun
        // her tazelemesinde tam sıralama demekti.
        try db.create(
            index: "channel_byPlaylistOrder",
            on: "channel",
            columns: ["playlistId", "sortOrder", "name"]
        )
        // EPG eşleştirmesi bu kolon üzerinden yapılır.
        try db.create(index: "channel_byEpgId", on: "channel", columns: ["epgChannelId"])
        // Numarayla hızlı geçiş ("205'e geç").
        try db.create(
            index: "channel_byNumber",
            on: "channel",
            columns: ["playlistId", "number", "sortOrder"]
        )

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
            columns: ["playlistId", "categoryId", "title", "id"]
        )
        // Kategori seçilmemişken (varsayılan görünüm) sayfalama bu indeksi
        // kullanır; olmadan her `LIMIT/OFFSET` isteği tüm katalogu sıralıyordu.
        // `id` sıralamadaki beraberlik bozucu olduğu için indekste de var.
        try db.create(
            index: "movie_byPlaylistTitle",
            on: "movie",
            columns: ["playlistId", "title", "id"]
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
            t.column("isAdult", .boolean).notNull().defaults(to: false)
            t.column("detailsLoadedAt", .datetime)
        }
        try db.create(
            index: "series_byCategory",
            on: "series",
            columns: ["playlistId", "categoryId", "title", "id"]
        )
        // Kategori seçilmemişken (varsayılan görünüm) sayfalama bu indeksi kullanır.
        try db.create(
            index: "series_byPlaylistTitle",
            on: "series",
            columns: ["playlistId", "title", "id"]
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
