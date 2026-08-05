#if DEBUG
import Foundation
import GRDB
import OctopusCore
import OctopusDomain

/// CI ekran görüntüleri için sahte katalog.
///
/// ## Neden gerekli?
/// Geliştirme Windows'ta yapılıyor; uygulama yalnızca CI'daki simülatörde
/// çalışıyor. Kaynak eklenmemiş bir uygulamada görülebilen tek ekran
/// karşılama ekranı — ana sayfa, katalog ızgarası ve detay başlığı hiç
/// görünmüyor. Yani **tasarım kör yapılıyor**.
///
/// Bu tohumlama kaynağı ve birkaç içeriği yazarak gerçek ekranların
/// kare alınmasını sağlıyor.
///
/// ⚠️ İki kapı birden: `#if DEBUG` **ve** açılış argümanı. Yayın
/// derlemesinde bu kod hiç derlenmez.
///
/// ⚠️ Görsel adresi verilmiyor: CI simülatöründen ağ isteği yapmak kareyi
/// dış servise bağımlı kılar. Yer tutucular da yerleşimi doğrulamaya yeter —
/// bakılan şey düzen, görselin kendisi değil.
public enum DemoCatalogSeeder {

    /// Açılış argümanıyla istendi mi?
    public static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-seedDemoData")
    }

    public static func seed(into database: AppDatabase) async throws {
        let playlistID: Playlist.ID = "demo"

        try await database.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO playlist
                        (id, name, kindType, m3uURL, createdAt, isActive)
                    VALUES (?, 'Demo Kaynak', 'm3u', 'http://example.com/demo.m3u',
                            '2026-01-01 00:00:00', 1)
                    """,
                arguments: [playlistID.value]
            )
        }

        let writer = CatalogWriter(database: database)
        try await writer.replaceLiveCatalog(
            playlistID: playlistID,
            categories: liveCategories(playlistID),
            channels: channels(playlistID)
        )
        try await writer.replaceMovieCatalog(
            playlistID: playlistID,
            categories: movieCategories(playlistID),
            movies: movies(playlistID)
        )

        Log.app.info("Demo katalog yazıldı — ekran görüntüsü modu")
    }

    // MARK: - Örnek içerik

    private static func liveCategories(_ playlistID: Playlist.ID) -> [MediaCategory] {
        ["Ulusal", "Spor", "Haber", "Çocuk"].enumerated().map { index, name in
            MediaCategory(
                id: EntityID.category(playlistID: playlistID, kind: .live, rawID: name),
                playlistID: playlistID,
                kind: .live,
                name: name,
                sortOrder: index
            )
        }
    }

    private static func channels(_ playlistID: Playlist.ID) -> [Channel] {
        let names = [
            "TRT 1", "Show TV", "Star TV", "Kanal D", "ATV",
            "TRT Spor", "A Spor", "NTV", "Habertürk", "TRT Çocuk"
        ]
        return names.enumerated().map { index, name in
            Channel(
                id: EntityID.channel(playlistID: playlistID, rawID: "\(index)"),
                playlistID: playlistID,
                name: name,
                streamKey: "\(index)",
                categoryID: EntityID.category(
                    playlistID: playlistID,
                    kind: .live,
                    rawID: index < 5 ? "Ulusal" : "Spor"
                ),
                number: 100 + index,
                sortOrder: index
            )
        }
    }

    private static func movieCategories(_ playlistID: Playlist.ID) -> [MediaCategory] {
        ["Aksiyon", "Dram", "Komedi"].enumerated().map { index, name in
            MediaCategory(
                id: EntityID.category(playlistID: playlistID, kind: .movie, rawID: name),
                playlistID: playlistID,
                kind: .movie,
                name: name,
                sortOrder: index
            )
        }
    }

    private static func movies(_ playlistID: Playlist.ID) -> [Movie] {
        let titles = [
            "Gölge Avcısı", "Son Tren", "Kayıp Şehir", "Beyaz Gece",
            "Uzak Kıyı", "Yedinci Kat", "Kırmızı Oda", "Sessiz Tanık",
            "Derin Sular", "Karanlık Orman", "Altın Anahtar", "Boş Sokak"
        ]
        return titles.enumerated().map { index, title in
            Movie(
                id: EntityID.movie(playlistID: playlistID, rawID: "\(index)"),
                playlistID: playlistID,
                title: title,
                streamKey: "\(index)",
                categoryID: EntityID.category(
                    playlistID: playlistID,
                    kind: .movie,
                    rawID: "Aksiyon"
                ),
                // Puan rozeti hem dolu hem boş hâliyle görünsün.
                rating: index % 3 == 0 ? nil : Double(60 + index * 3) / 10,
                addedAt: Date(timeIntervalSince1970: 1_700_000_000 - Double(index) * 86_400)
            )
        }
    }
}
#endif
