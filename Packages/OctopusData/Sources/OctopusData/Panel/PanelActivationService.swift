import Foundation
import OctopusCore
import OctopusDomain

/// Aktivasyon kodunu panelde çözer.
public struct PanelActivationService: ActivationRedeeming {

    private let endpoint: PanelEndpoint
    private let httpClient: HTTPClient

    public init(
        endpoint: PanelEndpoint = PanelEndpoint(),
        httpClient: HTTPClient? = nil
    ) {
        self.endpoint = endpoint
        // Kullanıcı kodu girmiş bekliyor; ayrıca panel tekrarlanan denemeleri
        // "too_many_attempts" ile cezalandırıyor — tek deneme yapılır.
        self.httpClient = httpClient ?? URLSessionHTTPClient(retryPolicy: .single)
    }

    /// Kodu panelde çözer.
    ///
    /// ⚠️ **POST**, GET değil. Uç nokta GET'e `405 method_not_allowed`
    /// döndürüyor; kod girişi bu yüzden hiç çalışmıyordu. Kod, sorgu
    /// dizesinde değil JSON gövdesinde gidiyor — sorgu dizesindeki değerler
    /// sunucu erişim kayıtlarına düşer, aktivasyon kodu ise tek kullanımlık
    /// bir sırdır.
    public func redeem(code: String) async throws -> ActivationResult {
        guard let normalized = Self.normalizeCode(code) else {
            throw ActivationError.invalidFormat
        }

        let body: Data
        do {
            body = try JSONEncoder().encode(["code": normalized])
        } catch {
            throw AppError.invalidResponse(reason: "Aktivasyon isteği hazırlanamadı")
        }

        let response: HTTPResponse
        do {
            response = try await httpClient.post(
                endpoint.activationRedeem,
                body: body,
                headers: [:]
            )
        } catch let error as AppError where error == .unauthorized {
            // Panel geçersiz kodu 401/403 ile de bildirebiliyor.
            throw ActivationError.notFound
        } catch {
            throw AppError.wrap(error)
        }

        // ⚠️ Kodun kendisi **loglanmıyor**: tek kullanımlık bir sır ve
        // cihaz logları paylaşılabiliyor. Durum kodu ile panelin hata
        // anahtarı, sorunu ayırt etmeye yetiyor.
        Log.network.notice(
            """
            Aktivasyon cevabı: HTTP \(response.statusCode) · \
            \(Self.errorKey(in: response.data) ?? "hatasız", privacy: .public) · \
            alanlar=[\(Self.fieldNames(in: response.data), privacy: .public)]
            """
        )

        return try Self.parse(response)
    }

    /// Cevaptaki **alan adlarını** listeler.
    ///
    /// ⚠️ Yalnızca anahtarlar; değerler asla loglanmıyor (parola taşıyor).
    /// Panelin alan adları belgelenmiş değil ve ayrıştırma buna takıldığında
    /// tek teşhis yolu bu.
    private static func fieldNames(in data: Data) -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return "okunamadı" }

        return object.keys.sorted().joined(separator: ",")
    }

    /// Cevaptaki hata anahtarını teşhis için okur.
    private static func errorKey(in data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = object["error"] as? String,
            !error.isEmpty
        else { return nil }
        return error
    }

    /// Cevabı çözer.
    ///
    /// ⚠️ Gövde **durum kodundan önce** okunuyor: panel `invalid_code_format`
    /// gibi asıl sebebi 400 gövdesinde açıklıyor. Önce koda bakılsaydı
    /// kullanıcı "Beklenmeyen durum kodu: 400" görürdü.
    static func parse(_ response: HTTPResponse) throws -> ActivationResult {
        do {
            return try parse(response.data)
        } catch let error as ActivationError {
            throw error
        } catch {
            // Gövde okunamadı; başarısız durum kodu varsa asıl sebep odur.
            if !response.isSuccess {
                try URLSessionHTTPClient.validate(statusCode: response.statusCode)
            }
            throw error
        }
    }

    static func parse(_ data: Data) throws -> ActivationResult {
        let dto: ActivationResponseDTO
        do {
            dto = try JSONDecoder().decode(ActivationResponseDTO.self, from: data)
        } catch {
            Log.network.error("Aktivasyon cevabı çözümlenemedi")
            throw AppError.invalidResponse(reason: "Aktivasyon cevabı okunamadı")
        }

        // ⚠️ Panel hatayı HTTP 200 gövdesinde bildiriyor; durum koduna
        // bakmak yetmez.
        if let error = dto.error, !error.isEmpty {
            throw ActivationError.fromServerCode(error)
        }

        guard let result = dto.toDomain() else {
            // ⚠️ Buraya düşmek "panel kodu kabul etti ama cevabındaki
            // alanları tanıyamadık" demektir — ağ ya da kod sorunu değil,
            // **sözleşme uyuşmazlığı**. Alan adları loglanıyor ki bir
            // sonraki denemede hangi ismi beklemek gerektiği görülsün.
            Log.network.error(
                "Aktivasyon: kod kabul edildi ama alanlar tanınmadı — panel sözleşmesi uyuşmuyor"
            )
            throw AppError.invalidResponse(reason: "Aktivasyon bilgileri eksik")
        }
        return result
    }
}

/// `/api/activation/redeem` cevabı.
struct ActivationResponseDTO: Decodable {

    /// Panelin asıl gönderdiği yapı: liste bilgileri **iç içe** geliyor.
    ///
    /// ```json
    /// { "success": true,
    ///   "playlist": { "playlist_type": "m3u", "m3u_url": "…" },
    ///   "theme": { "primary_color": "#E50914" } }
    /// ```
    ///
    /// ⚠️ Alanlar bir dönem en üst seviyede aranıyordu; panel kodu kabul
    /// ettiği hâlde "Aktivasyon bilgileri eksik" hatası bundandı. Düz
    /// (eski) biçim de okunmaya devam ediyor — hangisinin geleceğine
    /// panel sürümü karar veriyor.
    struct PlaylistPayload: Decodable {
        @Lenient var playlistType: String?
        @Lenient var playlistName: String?
        @Lenient var displayName: String?
        @Lenient var m3uUrl: String?
        @Lenient var epgUrl: String?
        @Lenient var serverUrl: String?
        @Lenient var username: String?
        @Lenient var password: String?
        @Lenient var playlistProtected: Bool?
        @Lenient var playlistPin: String?

        enum CodingKeys: String, CodingKey {
            case username, password
            case playlistType = "playlist_type"
            case playlistName = "playlist_name"
            case displayName = "display_name"
            case m3uUrl = "m3u_url"
            case epgUrl = "epg_url"
            case serverUrl = "server_url"
            case playlistProtected = "playlist_protected"
            case playlistPin = "playlist_pin"
        }
    }

    /// ⚠️ `@Lenient` **yok**: o sarmalayıcı yalnızca skaler tipleri
    /// tolere ediyor. Düz opsiyonel yeterli — sentezlenen `Decodable`
    /// anahtar yoksa `nil` bırakır, panel düz biçim gönderdiğinde de
    /// aşağıdaki yedek alanlar devreye girer.
    var playlist: PlaylistPayload?
    @Lenient var error: String?
    @Lenient var playlistType: String?
    @Lenient var playlistName: String?
    @Lenient var displayName: String?
    @Lenient var customerName: String?

    // Xtream alanları
    @Lenient var serverUrl: String?
    @Lenient var username: String?
    @Lenient var password: String?

    // M3U alanları
    @Lenient var m3uUrl: String?
    @Lenient var epgUrl: String?

    // ⚠️ Yedek alan adları. Panelin başarı cevabındaki isimler belgelenmiş
    // değil ve sürümden sürüme değişiyor; bunlar **yalnızca birincil ad
    // yoksa** okunuyor. Tanınmayan bir cevapta hangi adın geldiği
    // `Aktivasyon cevabı: … alanlar=[…]` logunda görünür.
    @Lenient var type: String?
    @Lenient var url: String?
    @Lenient var host: String?
    @Lenient var server: String?
    @Lenient var user: String?
    @Lenient var pass: String?
    @Lenient var playlistUrl: String?

    @Lenient var playlistProtected: Bool?

    // Bayi markası
    @Lenient var resellerName: String?
    @Lenient var resellerLogoUrl: String?
    @Lenient var resellerPrimaryColor: String?

    /// Bayinin teması.
    ///
    /// ⚠️ Panelin **gerçekte** gönderdiği yer burası:
    /// `"theme": { "theme_key": "red_black", "primary_color": "#E50914" }`.
    /// Renk yalnızca düz `reseller_primary_color` alanından okunuyordu ve o
    /// alan hiç gelmiyordu — bayinin rengi bu yüzden uygulamaya hiç
    /// yansımıyor, herkes varsayılan maviyi görüyordu.
    struct ThemePayload: Decodable {
        @Lenient var themeKey: String?
        @Lenient var primaryColor: String?

        enum CodingKeys: String, CodingKey {
            case themeKey = "theme_key"
            case primaryColor = "primary_color"
        }
    }

    var theme: ThemePayload?
    /// Aktivasyon servisinin canlı cevabında marka bilgileri bu nesnede gelir.
    /// Aynı yapı bayi yapılandırma servisiyle paylaşıldığı için tek sözleşme
    /// tipi kullanılır; alan adları iki yerde birbirinden kopmaz.
    var resellerConfig: ResellerConfigDTO?
    /// Bayi adı bazı panellerde `app_name` olarak geliyor.
    @Lenient var appName: String?

    enum CodingKeys: String, CodingKey {
        case playlist, error, username, password
        case type, url, host, server, user, pass
        case playlistUrl = "playlist_url"
        case playlistType = "playlist_type"
        case playlistName = "playlist_name"
        case displayName = "display_name"
        case customerName = "customer_name"
        case serverUrl = "server_url"
        case m3uUrl = "m3u_url"
        case epgUrl = "epg_url"
        case playlistProtected = "playlist_protected"
        case resellerName = "reseller_name"
        case resellerLogoUrl = "reseller_logo_url"
        case resellerPrimaryColor = "reseller_primary_color"
        case theme
        case resellerConfig = "reseller_config"
        case appName = "app_name"
    }

    func toDomain() -> ActivationResult? {
        guard let kind = resolveKind() else { return nil }

        // Ad sırası: bayinin belirlediği görünen ad → liste adı → varsayılan.
        // İç içe gelen alanlar önce okunur.
        let name = [
            playlist?.displayName, playlist?.playlistName, displayName, playlistName
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Listem"

        // Marka: önce panelin gerçekte gönderdiği `theme`, sonra düz alanlar.
        //
        // ⚠️ Renk `theme.primary_color`'dan okunmazsa bayinin markası hiç
        // uygulanmıyor — panel bu alanı düz `reseller_primary_color` olarak
        // göndermiyor.
        let colorHex = theme?.primaryColor
            ?? resellerConfig?.theme?.primaryColor
            ?? resellerPrimaryColor
        let brandName = [resellerName, appName, resellerConfig?.appName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        let logoURL = [resellerLogoUrl, resellerConfig?.logoUrl]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            .flatMap { URL(string: $0) }

        let branding: BrandConfiguration? = (
            colorHex != nil || brandName != nil || logoURL != nil
        ) ? BrandConfiguration(
            primaryColorHex: colorHex,
            resellerName: brandName,
            logoURL: logoURL
        ) : nil

        // Parola: panelin ayrı alanı → yoksa bağlantının içindeki.
        let password: String? = kind.isXtream
            ? (effectivePassword ?? xtreamFromLink?.password)
            : nil

        return ActivationResult(
            kind: kind,
            password: password,
            displayName: name,
            customerName: customerName,
            branding: branding,
            isProtected: effectiveProtected
        )
    }

    /// Okuma sırası: **iç içe `playlist` nesnesi → düz alan → yedek ad.**
    private var effectiveType: String? { playlist?.playlistType ?? playlistType ?? type }

    private var effectiveServer: String? {
        playlist?.serverUrl ?? serverUrl ?? host ?? server ?? url
    }

    private var effectiveUsername: String? {
        [playlist?.username, username, user].compactMap { $0 }.first { !$0.isEmpty }
    }

    var effectivePassword: String? {
        [playlist?.password, password, pass].compactMap { $0 }.first { !$0.isEmpty }
    }

    private var effectiveM3U: String? {
        playlist?.m3uUrl ?? m3uUrl ?? playlistUrl ?? url
    }

    private var effectiveProtected: Bool {
        playlist?.playlistProtected ?? playlistProtected ?? false
    }

    /// M3U bağlantısı Xtream kimliği taşıyorsa çözülmüş hâli.
    ///
    /// ⚠️ Panel `playlist_type: "m3u"` dese bile bakılıyor: tür alanı
    /// bağlantının **biçimini** anlatıyor, hesabın türünü değil.
    /// Bu kaynakta panel M3U diyordu ama adres bir Xtream `get.php`
    /// bağlantısıydı ve 250 MB'lık liste indiriliyordu.
    private var xtreamFromLink: XtreamLink.Credentials? {
        guard
            let raw = effectiveM3U,
            let url = URL(string: normalizedURLString(raw))
        else { return nil }
        return XtreamLink.credentials(from: url)
    }

    private func resolveKind() -> Playlist.Kind? {
        // Bağlantıdan Xtream çıkıyorsa tür alanına bakılmaksızın o kazanır.
        if let credentials = xtreamFromLink {
            return .xtream(host: credentials.host, username: credentials.username)
        }

        switch effectiveType?.lowercased() {
        case "xtream":
            guard let server = effectiveServer,
                  let hostURL = URL(string: normalizedURLString(server)),
                  let username = effectiveUsername, !username.isEmpty
            else { return nil }
            return .xtream(host: hostURL, username: username)

        case "m3u", "m3u_plus":
            guard let raw = effectiveM3U,
                  let playlistURL = URL(string: normalizedURLString(raw))
            else { return nil }
            return .m3u(url: playlistURL)

        default:
            // Tür bildirilmemişse alanlardan çıkarım yapılır: bazı paneller
            // yalnızca dolu alanları gönderiyor.
            //
            // ⚠️ Xtream önce denenir: kullanıcı adı varsa adres bir M3U
            // bağlantısı değil panel adresidir.
            if let server = effectiveServer,
               let username = effectiveUsername, !username.isEmpty,
               let hostURL = URL(string: normalizedURLString(server)) {
                return .xtream(host: hostURL, username: username)
            }
            if let raw = effectiveM3U,
               let playlistURL = URL(string: normalizedURLString(raw)) {
                return .m3u(url: playlistURL)
            }
            return nil
        }
    }

    /// Panel adresi şemasız gönderebiliyor.
    private func normalizedURLString(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "http://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }
}
