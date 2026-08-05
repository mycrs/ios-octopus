import Foundation

// İçerik okuma sözleşmeleri.
//
// ⚠️ Bunlar PROTOKOLDÜR. Feature modülleri yalnızca bunları görür;
// arkasında Xtream mi, M3U mu, SQLite mı olduğunu bilmez ve bilmemelidir.
//
// OFFLINE-FIRST SÖZLEŞMESİ:
// Her `fetch...` çağrısı ÖNCE yerel veritabanını döndürür. Ağ tazelemesi
// arka planda olur ve `observe...` akışını tetikler. UI asla boş ekran beklemez.

// MARK: - Kaynaklar

public protocol PlaylistRepository: Sendable {
    func all() async throws -> [Playlist]
    func playlist(id: Playlist.ID) async throws -> Playlist?
    func activePlaylist() async throws -> Playlist?

    /// Kaynağı doğrular ve kaydeder. Parola Keychain'e yazılır, entity'ye girmez.
    func add(_ playlist: Playlist, password: String?) async throws
    func update(_ playlist: Playlist) async throws
    func setActive(id: Playlist.ID) async throws

    /// Kaynağı ve ona ait TÜM içeriği siler (cascade).
    func delete(id: Playlist.ID) async throws
}

/// Kaynağı **kaydetmeden önce** doğrular.
///
/// Depodan ayrı bir sözleşme olmasının sebebi: doğrulama sırasında parola
/// henüz Keychain'de değildir, kullanıcının az önce yazdığı değerdir.
/// Depoya karıştırılsaydı "önce kaydet sonra dene" gibi ters bir akış
/// gerekirdi ve hatalı bilgiyle kaynak kaydedilmiş olurdu.
public protocol PlaylistValidating: Sendable {
    func validate(_ playlist: Playlist, password: String?) async throws -> ProviderAccount
}

// MARK: - Canlı TV

public protocol ChannelRepository: Sendable {
    func categories(playlistID: Playlist.ID) async throws -> [MediaCategory]

    /// `categoryID` nil ise tüm kanallar.
    func channels(
        playlistID: Playlist.ID,
        categoryID: MediaCategory.ID?
    ) async throws -> [Channel]

    func channel(id: Channel.ID) async throws -> Channel?

    /// Ad üzerinden arama (FTS destekli).
    func search(
        query: String,
        playlistID: Playlist.ID,
        limit: Int
    ) async throws -> [Channel]

    /// Liste canlı olarak değiştiğinde (senkronizasyon bitince) yeniden yayınlar.
    func observeChannels(
        playlistID: Playlist.ID,
        categoryID: MediaCategory.ID?
    ) -> AsyncStream<[Channel]>
}

// MARK: - Filmler

public protocol VODRepository: Sendable {
    func categories(playlistID: Playlist.ID) async throws -> [MediaCategory]

    func movies(
        playlistID: Playlist.ID,
        categoryID: MediaCategory.ID?,
        limit: Int,
        offset: Int
    ) async throws -> [Movie]

    func movie(id: Movie.ID) async throws -> Movie?

    /// Detay sayfası için zengin metadata (özet, oyuncular…) — gerekirse ağdan çeker.
    func loadDetails(id: Movie.ID) async throws -> Movie

    func search(query: String, playlistID: Playlist.ID, limit: Int) async throws -> [Movie]

    /// Son eklenenler — ana sayfa rafı.
    func recentlyAdded(playlistID: Playlist.ID, limit: Int) async throws -> [Movie]
}

// MARK: - Diziler

public protocol SeriesRepository: Sendable {
    func categories(playlistID: Playlist.ID) async throws -> [MediaCategory]

    func series(
        playlistID: Playlist.ID,
        categoryID: MediaCategory.ID?,
        limit: Int,
        offset: Int
    ) async throws -> [Series]

    func series(id: Series.ID) async throws -> Series?
    func seasons(seriesID: Series.ID) async throws -> [Season]
    func episodes(seriesID: Series.ID, seasonNumber: Int) async throws -> [Episode]
    func episode(id: Episode.ID) async throws -> Episode?

    /// Sezon/bölüm ağacını sağlayıcıdan çeker (Xtream'de ayrı bir istektir).
    func loadDetails(id: Series.ID) async throws

    func search(query: String, playlistID: Playlist.ID, limit: Int) async throws -> [Series]
}

// MARK: - EPG

public protocol EPGRepository: Sendable {
    /// Belirtilen anda yayında olan program.
    func nowPlaying(epgChannelID: String, at date: Date) async throws -> EPGProgram?

    /// Birden çok kanal için tek seferde — kanal listesinde N+1 sorgusunu önler.
    func nowPlaying(
        epgChannelIDs: [String],
        at date: Date
    ) async throws -> [String: EPGProgram]

    /// Zaman aralığındaki tüm programlar (EPG ızgarası için).
    func programs(
        epgChannelID: String,
        from: Date,
        to: Date
    ) async throws -> [EPGProgram]

    /// Süresi geçmiş kayıtları temizler — veritabanı şişmesin.
    func purgePrograms(before date: Date) async throws
}
