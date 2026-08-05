import Foundation
import OctopusCore
import OctopusDomain

/// Xtream Codes paneli sağlayıcısı.
///
/// API tek bir uç noktadır: `player_api.php?username=&password=&action=`
/// Akış adresleri ayrı bir düzendedir ve kimlik bilgisi **URL içinde** taşınır:
/// `{taban}/live/{kullanıcı}/{parola}/{stream_id}.{uzantı}`
public struct XtreamContentProvider: ContentProvider {

    /// Canlı yayın için istenen konteyner.
    public enum LiveFormat: String, Sendable {
        /// HLS — AVPlayer açar, PiP/AirPlay/arka plan sesi kazanılır.
        case hls = "m3u8"
        /// Ham MPEG-TS — VLC gerektirir ama her panelde çalışır.
        case mpegTS = "ts"
    }

    private let baseURL: URL
    private let username: String
    private let password: String
    private let playlistID: Playlist.ID
    private let httpClient: HTTPClient
    private let liveFormat: LiveFormat
    private let decoder = JSONDecoder()

    public init(
        baseURL: URL,
        username: String,
        password: String,
        playlistID: Playlist.ID,
        httpClient: HTTPClient,
        liveFormat: LiveFormat = .hls
    ) {
        self.baseURL = baseURL
        self.username = username
        self.password = password
        self.playlistID = playlistID
        self.httpClient = httpClient
        self.liveFormat = liveFormat
    }

    public var streamHeaders: [String: String] {
        ["User-Agent": URLSessionHTTPClient.defaultUserAgent]
    }

    // MARK: - Kimlik doğrulama

    public func authenticate() async throws -> ProviderAccount {
        let data = try await httpClient.get(apiURL(action: nil), headers: [:])
        let response = try decode(XtreamAuthResponse.self, from: data, context: "kimlik doğrulama")

        guard let userInfo = response.userInfo else {
            throw AppError.invalidResponse(reason: "Hesap bilgisi alınamadı")
        }

        // ⚠️ Paneller geçersiz girişte de HTTP 200 döner; `auth: 0` veya
        // `status != Active` alanına bakmadan başarı varsayılamaz.
        guard userInfo.isAuthenticated else {
            throw AppError.unauthorized
        }

        return userInfo.toDomain()
    }

    // MARK: - Kategoriler

    public func fetchCategories(kind: MediaCategory.Kind) async throws -> [MediaCategory] {
        let action: String
        switch kind {
        case .live: action = "get_live_categories"
        case .movie: action = "get_vod_categories"
        case .series: action = "get_series_categories"
        }

        let data = try await httpClient.get(apiURL(action: action), headers: [:])
        let dtos = try decode([XtreamCategoryDTO].self, from: data, context: "kategoriler")

        // Sıra panelin döndürdüğü sıradır — kullanıcı alıştığı düzeni görsün.
        return dtos.enumerated().compactMap { index, dto in
            dto.toDomain(playlistID: playlistID, kind: kind, sortOrder: index)
        }
    }

    // MARK: - Katalog

    public func fetchChannels(categoryID: MediaCategory.ID?) async throws -> [Channel] {
        let url = apiURL(action: "get_live_streams", categoryID: categoryID)
        let data = try await httpClient.get(url, headers: [:])
        let dtos = try decode([XtreamLiveStreamDTO].self, from: data, context: "kanallar")

        let channels = dtos.enumerated().compactMap { index, dto in
            dto.toDomain(playlistID: playlistID, sortOrder: index)
        }
        logDropped(total: dtos.count, kept: channels.count, kind: "kanal")
        return channels
    }

    public func fetchMovies(categoryID: MediaCategory.ID?) async throws -> [Movie] {
        let url = apiURL(action: "get_vod_streams", categoryID: categoryID)
        let data = try await httpClient.get(url, headers: [:])
        let dtos = try decode([XtreamVODStreamDTO].self, from: data, context: "filmler")

        let movies = dtos.compactMap { $0.toDomain(playlistID: playlistID) }
        logDropped(total: dtos.count, kept: movies.count, kind: "film")
        return movies
    }

    /// Künye ayrı bir istektir; liste ucu yalnızca ad, afiş ve puan verir.
    public func fetchMovieDetails(streamKey: String) async throws -> Movie {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/player_api.php"
        components?.queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password),
            URLQueryItem(name: "action", value: "get_vod_info"),
            URLQueryItem(name: "vod_id", value: streamKey)
        ]
        guard let url = components?.url else {
            throw AppError.invalidResponse(reason: "Film adresi kurulamadı")
        }

        let data = try await httpClient.get(url, headers: [:])
        let dto = try decode(XtreamVODInfoDTO.self, from: data, context: "film ayrıntısı")

        // Zenginleştirilecek taban: yalnızca kimlik ve akış anahtarı bilinir,
        // gerisi cevaptan gelir. Çağıran bunu mevcut kayıtla birleştirir.
        let base = Movie(
            id: EntityID.movie(playlistID: playlistID, rawID: streamKey),
            playlistID: playlistID,
            title: dto.movieData?.name ?? "",
            streamKey: streamKey
        )
        return dto.enrich(base)
    }

    public func fetchSeries(categoryID: MediaCategory.ID?) async throws -> [Series] {
        let url = apiURL(action: "get_series", categoryID: categoryID)
        let data = try await httpClient.get(url, headers: [:])
        let dtos = try decode([XtreamSeriesDTO].self, from: data, context: "diziler")

        let series = dtos.compactMap { $0.toDomain(playlistID: playlistID) }
        logDropped(total: dtos.count, kept: series.count, kind: "dizi")
        return series
    }

    /// Sezon ve bölüm ağacı ayrı bir istektir; dizi listesinde gelmez.
    public func fetchSeriesDetails(
        streamKey: String
    ) async throws -> (seasons: [Season], episodes: [Episode]) {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/player_api.php"
        components?.queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password),
            URLQueryItem(name: "action", value: "get_series_info"),
            URLQueryItem(name: "series_id", value: streamKey)
        ]
        guard let url = components?.url else {
            throw AppError.invalidResponse(reason: "Dizi adresi kurulamadı")
        }

        let data = try await httpClient.get(url, headers: [:])
        let dto = try decode(XtreamSeriesInfoDTO.self, from: data, context: "dizi ayrıntısı")

        let seriesID = EntityID.series(playlistID: playlistID, rawID: streamKey)
        let result = dto.toDomain(seriesID: seriesID)

        guard !result.episodes.isEmpty else {
            // Bölümsüz dizi oynatılamaz; boş liste göstermek yerine
            // kullanıcıya durumu bildirmek daha doğru.
            throw AppError.notFound
        }
        return result
    }

    /// Xtream panelleri rehberi ayrı bir uçta sunar.
    public var epgSourceURL: URL? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/xmltv.php"
        components?.queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password)
        ]
        return components?.url
    }

    // MARK: - Akış adresleri
    //
    // Kimlik bilgisi URL'e gömülür — Xtream'in tasarımı böyledir.
    // Bu adresler loglanmamalıdır.

    public func streamURL(for channel: Channel) -> URL? {
        makeStreamURL(
            section: "live",
            key: channel.streamKey,
            extension: liveFormat.rawValue
        )
    }

    public func streamURL(for movie: Movie) -> URL? {
        makeStreamURL(
            section: "movie",
            key: movie.streamKey,
            extension: movie.containerExtension ?? "mp4"
        )
    }

    public func streamURL(for episode: Episode) -> URL? {
        makeStreamURL(
            section: "series",
            key: episode.streamKey,
            extension: episode.containerExtension ?? "mp4"
        )
    }

    // MARK: - URL kurucular

    private func makeStreamURL(section: String, key: String, extension ext: String) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = "/\(section)/\(username)/\(password)/\(key).\(ext)"
        components.query = nil
        return components.url
    }

    private func apiURL(action: String?, categoryID: MediaCategory.ID? = nil) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/player_api.php"

        var items = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password)
        ]
        if let action {
            items.append(URLQueryItem(name: "action", value: action))
        }
        if let categoryID {
            // Panel kendi ham kimliğini bekler; ekranlar global kimlik taşır.
            items.append(
                URLQueryItem(
                    name: "category_id",
                    value: EntityID.rawValue(from: categoryID.value)
                )
            )
        }
        components?.queryItems = items

        // Taban adres doğrulanarak kaydedildiği için bu kurulum başarısız olmaz;
        // yine de force unwrap kullanılmaz.
        return components?.url ?? baseURL
    }

    // MARK: - Yardımcılar

    private func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        context: String
    ) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            // Bazı paneller hata durumunda JSON yerine HTML döndürür.
            Log.network.error("\(context) çözümlenemedi: \(String(describing: error))")
            throw AppError.invalidResponse(reason: "\(context) okunamadı")
        }
    }

    /// Eksik alanlar yüzünden atlanan kayıtları görünür kılar.
    ///
    /// Sessizce atlanırsa "kanallarım eksik" şikâyetinin sebebi bulunamaz.
    private func logDropped(total: Int, kept: Int, kind: String) {
        let dropped = total - kept
        guard dropped > 0 else { return }
        Log.parser.warning("\(dropped)/\(total) \(kind) kaydı eksik alan yüzünden atlandı")
    }
}
