import Foundation
import OctopusDomain

// Xtream Codes `player_api.php` cevaplarının veri aktarım tipleri.
//
// ⚠️ Tüm alanlar `@Lenient` — bkz. LenientDecoding.swift.
// Paneller aynı alanı sürüme göre sayı veya dizgi döndürür ve katı kod
// çözme tek tutarsız kayıt yüzünden bütün listeyi düşürür.
//
// Bu tipler Data katmanına özeldir; Domain onları görmez.

// MARK: - Kimlik doğrulama

struct XtreamAuthResponse: Decodable {
    let userInfo: XtreamUserInfo?
    let serverInfo: XtreamServerInfo?

    enum CodingKeys: String, CodingKey {
        case userInfo = "user_info"
        case serverInfo = "server_info"
    }
}

struct XtreamUserInfo: Decodable {
    @Lenient var username: String?
    @Lenient var status: String?
    /// Epoch saniyesi; süresiz hesaplarda boş gelir.
    @Lenient var expDate: Int?
    @Lenient var isTrial: Bool?
    @Lenient var activeCons: Int?
    @Lenient var maxConnections: Int?
    /// Bazı paneller `auth: 0` ile başarısızlığı 200 içinde bildirir.
    @Lenient var auth: Int?

    enum CodingKeys: String, CodingKey {
        case username, status, auth
        case expDate = "exp_date"
        case isTrial = "is_trial"
        case activeCons = "active_cons"
        case maxConnections = "max_connections"
    }

    /// Hesap kullanılabilir mi?
    ///
    /// Panellerin çoğu geçersiz girişte HTTP 200 + `auth: 0` döner —
    /// yalnızca durum koduna bakmak yeterli değildir.
    var isAuthenticated: Bool {
        if let auth, auth == 0 { return false }
        guard let status else { return true }
        return status.caseInsensitiveCompare("Active") == .orderedSame
    }

    func toDomain() -> ProviderAccount {
        ProviderAccount(
            username: username ?? "",
            expiresAt: XtreamDate.fromEpoch(expDate),
            isTrial: isTrial ?? false,
            maxConnections: maxConnections ?? 1,
            activeConnections: activeCons ?? 0
        )
    }
}

struct XtreamServerInfo: Decodable {
    @Lenient var url: String?
    @Lenient var port: String?
    @Lenient var httpsPort: String?
    @Lenient var serverProtocol: String?

    enum CodingKeys: String, CodingKey {
        case url, port
        case httpsPort = "https_port"
        case serverProtocol = "server_protocol"
    }
}

// MARK: - Kategoriler

struct XtreamCategoryDTO: Decodable {
    @Lenient var categoryID: String?
    @Lenient var categoryName: String?

    enum CodingKeys: String, CodingKey {
        case categoryID = "category_id"
        case categoryName = "category_name"
    }

    func toDomain(
        playlistID: Playlist.ID,
        kind: MediaCategory.Kind,
        sortOrder: Int
    ) -> MediaCategory? {
        guard let categoryID, let categoryName else { return nil }
        return MediaCategory(
            id: EntityID.category(playlistID: playlistID, kind: kind, rawID: categoryID),
            playlistID: playlistID,
            kind: kind,
            name: categoryName,
            sortOrder: sortOrder
        )
    }
}

// MARK: - Canlı yayın

struct XtreamLiveStreamDTO: Decodable {
    @Lenient var streamID: Int?
    @Lenient var name: String?
    @Lenient var streamIcon: String?
    @Lenient var epgChannelID: String?
    @Lenient var categoryID: String?
    @Lenient var num: Int?
    /// Yetişkin içerik bayrağı — ebeveyn kilidi bunu okur.
    @Lenient var isAdult: Bool?

    enum CodingKeys: String, CodingKey {
        case name, num
        case streamID = "stream_id"
        case streamIcon = "stream_icon"
        case epgChannelID = "epg_channel_id"
        case categoryID = "category_id"
        case isAdult = "is_adult"
    }

    func toDomain(playlistID: Playlist.ID, sortOrder: Int) -> Channel? {
        // Akış kimliği olmadan yayın açılamaz; adsız kanal da listelenemez.
        guard let streamID, let name else { return nil }
        let rawID = String(streamID)

        return Channel(
            id: EntityID.channel(playlistID: playlistID, rawID: rawID),
            playlistID: playlistID,
            name: name,
            streamKey: rawID,
            logoURL: streamIcon.flatMap { URL(string: $0) },
            categoryID: categoryID.map {
                EntityID.category(playlistID: playlistID, kind: .live, rawID: $0)
            },
            epgChannelID: epgChannelID,
            number: num,
            sortOrder: sortOrder,
            isAdult: isAdult ?? false
        )
    }
}

// MARK: - Film

struct XtreamVODStreamDTO: Decodable {
    @Lenient var streamID: Int?
    @Lenient var name: String?
    @Lenient var streamIcon: String?
    @Lenient var categoryID: String?
    @Lenient var containerExtension: String?
    @Lenient var rating: Double?
    @Lenient var added: Int?
    @Lenient var isAdult: Bool?

    enum CodingKeys: String, CodingKey {
        case name, rating, added
        case streamID = "stream_id"
        case streamIcon = "stream_icon"
        case categoryID = "category_id"
        case containerExtension = "container_extension"
        case isAdult = "is_adult"
    }

    func toDomain(playlistID: Playlist.ID) -> Movie? {
        guard let streamID, let name else { return nil }
        let rawID = String(streamID)

        return Movie(
            id: EntityID.movie(playlistID: playlistID, rawID: rawID),
            playlistID: playlistID,
            title: name,
            streamKey: rawID,
            // Uzantı olmadan akış URL'si kurulamaz; panellerin varsayılanı mp4.
            containerExtension: containerExtension ?? "mp4",
            posterURL: streamIcon.flatMap { URL(string: $0) },
            categoryID: categoryID.map {
                EntityID.category(playlistID: playlistID, kind: .movie, rawID: $0)
            },
            rating: rating,
            isAdult: isAdult ?? false,
            addedAt: XtreamDate.fromEpoch(added)
        )
    }
}

// MARK: - Dizi

struct XtreamSeriesDTO: Decodable {
    @Lenient var seriesID: Int?
    @Lenient var name: String?
    @Lenient var cover: String?
    @Lenient var categoryID: String?
    @Lenient var plot: String?
    @Lenient var cast: String?
    @Lenient var genre: String?
    @Lenient var rating: Double?
    @Lenient var releaseDate: String?
    @Lenient var lastModified: Int?
    @Lenient var backdropPath: [String]?

    enum CodingKeys: String, CodingKey {
        case name, cover, plot, cast, genre, rating
        case seriesID = "series_id"
        case categoryID = "category_id"
        case releaseDate = "releaseDate"
        case lastModified = "last_modified"
        case backdropPath = "backdrop_path"
    }

    func toDomain(playlistID: Playlist.ID) -> Series? {
        guard let seriesID, let name else { return nil }
        let rawID = String(seriesID)

        return Series(
            id: EntityID.series(playlistID: playlistID, rawID: rawID),
            playlistID: playlistID,
            title: name,
            streamKey: rawID,
            posterURL: cover.flatMap { URL(string: $0) },
            backdropURL: backdropPath?.first.flatMap { URL(string: $0) },
            categoryID: categoryID.map {
                EntityID.category(playlistID: playlistID, kind: .series, rawID: $0)
            },
            plot: plot,
            rating: rating,
            genres: XtreamList.split(genre),
            cast: XtreamList.split(cast),
            releaseDate: XtreamDate.fromDayString(releaseDate),
            lastModified: XtreamDate.fromEpoch(lastModified)
        )
    }
}

// `backdrop_path` bazen dizi bazen tek dizgi döner.
extension Array: LenientlyDecodable where Element == String {
    static func decodeLeniently(from container: SingleValueDecodingContainer) -> [String]? {
        if let values = try? container.decode([String].self) { return values }
        if let single = try? container.decode(String.self), !single.isEmpty { return [single] }
        return nil
    }
}

/// Xtream tür/oyuncu alanları virgülle ayrılmış tek dizgidir.
enum XtreamList {
    static func split(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        return raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
