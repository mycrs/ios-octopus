import Foundation
import OctopusDomain

/// Uzak içerik kaynağı sözleşmesi — **Data katmanının iç soyutlaması**.
///
/// İki implementasyonu olacak (Faz 2):
/// - `XtreamContentProvider` — `player_api.php` JSON API
/// - `M3UContentProvider`    — `#EXTINF` playlist + XMLTV EPG
///
/// Repository'ler bu protokolü kullanır; hangi kaynak olduğunu Domain bilmez.
/// Yeni bir sağlayıcı türü eklemek = bu protokolün yeni bir implementasyonu.
/// Domain, Feature ve App'te **tek satır** değişmez.
public protocol ContentProvider: Sendable {

    /// Hesabı doğrular. Başarısızsa `AppError.unauthorized` fırlatır.
    func authenticate() async throws -> ProviderAccount

    func fetchCategories(kind: MediaCategory.Kind) async throws -> [MediaCategory]

    func fetchChannels(categoryID: MediaCategory.ID?) async throws -> [Channel]

    func fetchMovies(categoryID: MediaCategory.ID?) async throws -> [Movie]
    func fetchMovieDetails(streamKey: String) async throws -> Movie

    func fetchSeries(categoryID: MediaCategory.ID?) async throws -> [Series]
    /// Dizi ağacı tek istekte gelir (Xtream davranışı).
    func fetchSeriesDetails(streamKey: String) async throws -> (seasons: [Season], episodes: [Episode])

    /// XMLTV rehber dosyasının adresi. Kaynak EPG sunmuyorsa `nil`.
    ///
    /// ⚠️ Dosyanın kendisi burada **indirilmez**. 14.000 kanallı hesapta
    /// XMLTV yüzlerce megabayt olabiliyor; indirme ve çözümleme
    /// senkronizasyon servisinde akış halinde yapılır.
    var epgSourceURL: URL? { get }

    // MARK: - Akış adresi kurulumu

    func streamURL(for channel: Channel) -> URL?
    func streamURL(for movie: Movie) -> URL?
    func streamURL(for episode: Episode) -> URL?

    /// İstek başlıkları (özellikle `User-Agent`).
    /// Birçok panel beklenmeyen UA'ya 403 döner — motorlar bunu iletmek zorundadır.
    var streamHeaders: [String: String] { get }
}

/// `Playlist.Kind`'a göre doğru provider'ı üretir.
///
/// Bu fabrika Data katmanının **tek giriş kapısıdır**; App yalnızca bunu kurar.
public protocol ContentProviderFactory: Sendable {
    func makeProvider(for playlist: Playlist) async throws -> ContentProvider
}
