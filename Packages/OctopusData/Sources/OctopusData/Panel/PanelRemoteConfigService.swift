import Foundation
import OctopusCore
import OctopusDomain

/// Panel yapılandırmasını çeker ve çevrimdışı kullanım için saklar.
///
/// ⚠️ Ağ hatası **sessizce** ele alınır: panel erişilemezse uygulama
/// markasız veya kilitli açılmamalı, son bilinen yapılandırma kullanılmalı.
/// Bu yüzden `refresh()` fırlatmaz, `nil` döner.
public actor PanelRemoteConfigService: RemoteConfigProviding {

    private let endpoint: PanelEndpoint
    private let httpClient: HTTPClient
    private let store: UserDefaults
    private let now: @Sendable () -> Date

    private static let storageKey = "panel.appConfig"
    private static let fetchedAtKey = "panel.appConfig.fetchedAt"

    public init(
        endpoint: PanelEndpoint = PanelEndpoint(),
        httpClient: HTTPClient? = nil,
        store: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.endpoint = endpoint
        // Panel isteği kullanıcı beklerken yapılır; uzun yeniden denemeler
        // açılışı geciktirir.
        self.httpClient = httpClient ?? URLSessionHTTPClient(retryPolicy: .single)
        self.store = store
        self.now = now
    }

    public func refresh() async -> RemoteAppConfig? {
        do {
            let data = try await httpClient.get(endpoint.appConfig, headers: [:])
            let dto = try Self.decode(data)
            persist(dto)
            Log.network.info("Panel yapılandırması güncellendi")
            return dto.toDomain(fetchedAt: now())
        } catch {
            Log.network.info("Panel yapılandırması alınamadı, önbellek kullanılacak")
            return await cached()
        }
    }

    public func cached() async -> RemoteAppConfig? {
        guard let data = store.data(forKey: Self.storageKey),
              let dto = try? JSONDecoder().decode(RemoteAppConfigDTO.self, from: data)
        else { return nil }

        let fetchedAt = store.object(forKey: Self.fetchedAtKey) as? Date ?? now()
        return dto.toDomain(fetchedAt: fetchedAt)
    }

    private func persist(_ dto: RemoteAppConfigDTO) {
        guard let data = try? JSONEncoder().encode(dto) else { return }
        store.set(data, forKey: Self.storageKey)
        store.set(now(), forKey: Self.fetchedAtKey)
    }

    /// Cevap `{success, config:{…}}` sarmalayıcısıyla da düz nesne olarak da
    /// gelebiliyor; ikisi de kabul edilir.
    static func decode(_ data: Data) throws -> RemoteAppConfigDTO {
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(PanelEnvelope.self, from: data),
           let config = envelope.config {
            return config
        }
        do {
            return try decoder.decode(RemoteAppConfigDTO.self, from: data)
        } catch {
            throw AppError.invalidResponse(reason: "Panel yapılandırması okunamadı")
        }
    }
}

private struct PanelEnvelope: Decodable {
    let config: RemoteAppConfigDTO?
}

/// Panel cevabının aktarım tipi.
///
/// Tüm alanlar `@Lenient`: panel sürümleri arasında tip tutarsızlığı
/// görülüyor (`true` / `"true"` / `1`) ve tek alan yüzünden markanın
/// tamamen kaybolması kabul edilemez.
struct RemoteAppConfigDTO: Codable {

    @Lenient var announcementEnabled: Bool?
    @Lenient var announcementMessage: String?
    /// ⚠️ Panel bu alanı **`maintenance`** diye gönderiyor; kod
    /// `maintenance_mode` bekliyordu ve bakım modu hiç tetiklenmiyordu.
    /// Eski paneller `maintenance_mode` gönderebileceği için ikisi de okunuyor.
    @Lenient var maintenance: Bool?
    @Lenient var maintenanceMode: Bool?
    @Lenient var maintenanceMessage: String?
    /// Sunucu/kullanıcı/parola ile giriş açık mı? (Bayi kapatabiliyor.)
    @Lenient var xtreamLoginEnabled: Bool?
    @Lenient var whatsappUrl: String?
    @Lenient var telegramUrl: String?
    @Lenient var websiteUrl: String?
    @Lenient var primaryColor: String?
    @Lenient var resellerName: String?
    @Lenient var resellerLogoUrl: String?
    var theme: ThemeDTO?

    struct ThemeDTO: Codable {
        @Lenient var primaryColor: String?

        enum CodingKeys: String, CodingKey {
            case primaryColor = "primary_color"
        }
    }

    enum CodingKeys: String, CodingKey {
        case theme
        case announcementEnabled = "announcement_enabled"
        case announcementMessage = "announcement_message"
        case maintenance
        case maintenanceMode = "maintenance_mode"
        case maintenanceMessage = "maintenance_message"
        case xtreamLoginEnabled = "xtream_login_enabled"
        case whatsappUrl = "whatsapp_url"
        case telegramUrl = "telegram_url"
        case websiteUrl = "website_url"
        case primaryColor = "primary_color"
        case resellerName = "reseller_name"
        case resellerLogoUrl = "reseller_logo_url"
    }

    func toDomain(fetchedAt: Date) -> RemoteAppConfig {
        // Duyuru yalnızca AÇIKSA ve metni varsa gösterilir.
        let announcement = (announcementEnabled == true)
            ? announcementMessage.flatMap { Announcement(message: $0) }
            : nil

        // İkisinden biri açıksa bakım modu: panel sürümüne göre alan adı değişiyor.
        let isUnderMaintenance = (maintenance == true) || (maintenanceMode == true)
        let gate: ServiceGate = isUnderMaintenance
            ? .maintenance(message: maintenanceMessage)
            : .open

        return RemoteAppConfig(
            announcement: announcement,
            gate: gate,
            branding: BrandConfiguration(
                // `theme.primary_color` öncelikli; eski panellerde düz alan var.
                primaryColorHex: theme?.primaryColor ?? primaryColor,
                resellerName: resellerName,
                logoURL: resellerLogoUrl.flatMap { URL(string: $0) }
            ),
            contact: ContactChannels(
                whatsAppURL: whatsappUrl.flatMap { URL(string: $0) },
                telegramURL: telegramUrl.flatMap { URL(string: $0) },
                websiteURL: websiteUrl.flatMap { URL(string: $0) }
            ),
            // Panel bilgi vermiyorsa açık kabul edilir (bkz. Domain).
            isXtreamLoginEnabled: xtreamLoginEnabled ?? true,
            fetchedAt: fetchedAt
        )
    }
}

// `@Lenient` yalnızca kod çözmeyi biliyordu; önbelleğe yazabilmek için
// kodlama da gerekiyor.
extension Lenient: Encodable where Value: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let wrappedValue {
            try container.encode(wrappedValue)
        } else {
            try container.encodeNil()
        }
    }
}
