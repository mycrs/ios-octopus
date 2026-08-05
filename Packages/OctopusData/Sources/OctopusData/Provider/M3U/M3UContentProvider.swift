import Foundation
import OctopusCore
import OctopusDomain

/// M3U / M3U8 playlist sağlayıcısı.
///
/// Xtream'den yapısal olarak farklıdır: API yoktur, **tek bir dosya** vardır.
/// Kategoriler ve kanallar aynı indirmeden çıkar. Bu yüzden sonuç bir kez
/// çözümlenip saklanır — her çağrıda yeniden indirmek 20 MB'lık listelerde
/// kabul edilemez.
///
/// `actor` olmasının sebebi bu önbellek: eşzamanlı çağrılar aynı indirmeyi
/// tekrarlamamalı.
public actor M3UContentProvider: ContentProvider {

    private let sourceURL: URL
    private let epgURL: URL?
    private let playlistID: Playlist.ID
    private let httpClient: HTTPClient

    private var cachedResult: M3UParser.Result?
    /// Devam eden indirme — eşzamanlı çağrılar aynı işi beklesin.
    private var loadTask: Task<M3UParser.Result, Error>?

    public init(
        sourceURL: URL,
        epgURL: URL? = nil,
        playlistID: Playlist.ID,
        httpClient: HTTPClient
    ) {
        self.sourceURL = sourceURL
        self.epgURL = epgURL
        self.playlistID = playlistID
        self.httpClient = httpClient
    }

    public nonisolated var streamHeaders: [String: String] {
        ["User-Agent": URLSessionHTTPClient.defaultUserAgent]
    }

    // MARK: - Kimlik doğrulama
    //
    // M3U'da hesap kavramı yoktur. "Doğrulama", listenin indirilip
    // çözümlenebildiğini kanıtlamaktır.

    public func authenticate() async throws -> ProviderAccount {
        let result = try await load()

        guard !result.channels.isEmpty else {
            throw AppError.invalidResponse(reason: "Listede hiç kanal bulunamadı")
        }

        return ProviderAccount(
            username: sourceURL.host ?? "M3U",
            expiresAt: nil,
            isTrial: false,
            maxConnections: 1,
            activeConnections: 0
        )
    }

    // MARK: - Katalog

    public func fetchCategories(kind: MediaCategory.Kind) async throws -> [MediaCategory] {
        // Klasik M3U listeleri yalnızca canlı yayın taşır.
        guard kind == .live else { return [] }
        return try await load().categories
    }

    public func fetchChannels(categoryID: MediaCategory.ID?) async throws -> [Channel] {
        let channels = try await load().channels
        guard let categoryID else { return channels }
        return channels.filter { $0.categoryID == categoryID }
    }

    // M3U'da VOD/dizi yapısı yoktur. Boş dizi döndürmek doğru davranıştır:
    // hata fırlatmak senkronizasyonu gereksiz yere başarısız gösterirdi.
    public func fetchMovies(categoryID: MediaCategory.ID?) async throws -> [Movie] { [] }
    public func fetchSeries(categoryID: MediaCategory.ID?) async throws -> [Series] { [] }

    public func fetchMovieDetails(streamKey: String) async throws -> Movie {
        throw AppError.notFound
    }

    public func fetchSeriesDetails(
        streamKey: String
    ) async throws -> (seasons: [Season], episodes: [Episode]) {
        throw AppError.notFound
    }

    /// M3U kaynaklarında rehber adresi kullanıcıdan alınır (`#EXTM3U x-tvg-url`
    /// veya kaynak formundaki EPG alanı).
    public nonisolated var epgSourceURL: URL? { epgURL }

    // MARK: - Akış adresleri
    //
    // M3U'da adres zaten listede yazılıdır; `streamKey` adresin kendisidir.

    public nonisolated func streamURL(for channel: Channel) -> URL? {
        URL(string: channel.streamKey)
    }

    public nonisolated func streamURL(for movie: Movie) -> URL? {
        URL(string: movie.streamKey)
    }

    public nonisolated func streamURL(for episode: Episode) -> URL? {
        URL(string: episode.streamKey)
    }

    // MARK: - İndirme ve çözümleme

    private func load() async throws -> M3UParser.Result {
        if let cachedResult { return cachedResult }

        // Eşzamanlı çağrılar aynı indirmeyi tekrarlamasın.
        if let loadTask { return try await loadTask.value }

        let task = Task<M3UParser.Result, Error> { [sourceURL, playlistID, httpClient] in
            let data = try await httpClient.get(sourceURL, headers: [:])

            // IPTV listeleri her zaman UTF-8 değildir; Latin-1 yaygın ikinci seçenek.
            guard let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1)
            else {
                throw AppError.invalidResponse(reason: "Liste metne çevrilemedi")
            }

            return M3UParser.parse(text, playlistID: playlistID)
        }
        loadTask = task

        do {
            let result = try await task.value
            cachedResult = result
            loadTask = nil
            Log.parser.info("M3U çözümlendi: \(result.channels.count) kanal")
            return result
        } catch {
            // Başarısız indirme önbelleğe alınmaz; sonraki deneme yeniden istesin.
            loadTask = nil
            throw error
        }
    }

    /// Senkronizasyon yeniden çalıştığında taze liste istenir.
    public func invalidateCache() {
        cachedResult = nil
    }
}
