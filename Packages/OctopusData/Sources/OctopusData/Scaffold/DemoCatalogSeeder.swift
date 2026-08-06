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

    public static func seed(into database: AppDatabase, secrets: SecretStore) async throws {
        let playlistID: Playlist.ID = "demo"

        // Ham SQL yerine gerçek repository: tablo şeması burada tekrar
        // tahmin edilmiyor, üretimdeki aynı kod yolu kullanılıyor.
        let playlists = GRDBPlaylistRepository(database: database, secrets: secrets)

        // CI her sekme için uygulamayı ayrı ayrı başlatıyor; kaynak önceki
        // çalıştırmadan zaten diskte kalmış olabilir. Sil-sonra-ekle,
        // birincil anahtar çakışmasını engeller.
        try? await playlists.delete(id: playlistID)

        try await playlists.add(
            Playlist(
                id: playlistID,
                name: "Demo Kaynak",
                kind: .m3u(url: URL(string: "http://example.com/demo.m3u")!),
                createdAt: Date(),
                isActive: true
            ),
            password: nil
        )

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
                // ⚠️ Gerçek bir görsel yüklenmesi beklenmiyor — `example.com`
                // resim döndürmez, `RemoteImageView` yer tutucuya düşer.
                // Adres yalnızca **dolu olsun** diye var: ana sayfanın öne
                // çıkan bölümü yalnızca görseli olan içeriği seçiyor
                // (sağlayıcı poster vermemişse hero'da boş kutu olmasın diye)
                // — demo veri de bu kuralı geçmeli, aksi hâlde hero hiç
                // görünmez ve o bölüm doğrulanamaz.
                posterURL: URL(string: "https://example.com/poster/\(index).jpg"),
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
