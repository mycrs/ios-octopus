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

    public func redeem(code: String) async throws -> ActivationResult {
        guard let normalized = Self.normalizeCode(code) else {
            throw ActivationError.invalidFormat
        }

        var components = URLComponents(
            url: endpoint.activationRedeem,
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "code", value: normalized)]
        let url = components?.url ?? endpoint.activationRedeem

        let data: Data
        do {
            data = try await httpClient.get(url, headers: [:])
        } catch let error as AppError where error == .unauthorized {
            // Panel geçersiz kodu 401/403 ile de bildirebiliyor.
            throw ActivationError.notFound
        } catch {
            throw AppError.wrap(error)
        }

        return try Self.parse(data)
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
            throw AppError.invalidResponse(reason: "Aktivasyon bilgileri eksik")
        }
        return result
    }
}

/// `/api/activation/redeem` cevabı.
struct ActivationResponseDTO: Decodable {

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

    @Lenient var playlistProtected: Bool?

    // Bayi markası
    @Lenient var resellerName: String?
    @Lenient var resellerLogoUrl: String?
    @Lenient var resellerPrimaryColor: String?

    enum CodingKeys: String, CodingKey {
        case error, username, password
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
    }

    func toDomain() -> ActivationResult? {
        guard let kind = resolveKind() else { return nil }

        // Ad sırası: bayinin belirlediği görünen ad → liste adı → varsayılan.
        let name = [displayName, playlistName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Listem"

        let branding: BrandConfiguration? = (
            resellerName != nil || resellerLogoUrl != nil || resellerPrimaryColor != nil
        ) ? BrandConfiguration(
            primaryColorHex: resellerPrimaryColor,
            resellerName: resellerName,
            logoURL: resellerLogoUrl.flatMap { URL(string: $0) }
        ) : nil

        return ActivationResult(
            kind: kind,
            password: (kind.isXtream ? password : nil),
            displayName: name,
            customerName: customerName,
            branding: branding,
            isProtected: playlistProtected ?? false
        )
    }

    private func resolveKind() -> Playlist.Kind? {
        switch playlistType?.lowercased() {
        case "xtream":
            guard let serverUrl,
                  let host = URL(string: normalizedURLString(serverUrl)),
                  let username, !username.isEmpty
            else { return nil }
            return .xtream(host: host, username: username)

        case "m3u", "m3u_plus":
            guard let m3uUrl,
                  let url = URL(string: normalizedURLString(m3uUrl))
            else { return nil }
            return .m3u(url: url)

        default:
            // Tür bildirilmemişse alanlardan çıkarım yapılır: bazı paneller
            // yalnızca dolu alanları gönderiyor.
            if let serverUrl, let username, !username.isEmpty,
               let host = URL(string: normalizedURLString(serverUrl)) {
                return .xtream(host: host, username: username)
            }
            if let m3uUrl, let url = URL(string: normalizedURLString(m3uUrl)) {
                return .m3u(url: url)
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
