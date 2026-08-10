import Foundation
import OctopusCore
import OctopusDomain

/// Bayi kodunu panele sorup markalama ve sunucu listesini getirir.
///
/// ## Neden ayrı servis?
/// Global yapılandırma (`PanelRemoteConfigService`) **her kurulumda**
/// çekilir; bu ise yalnızca kullanıcı bir bayi kodu girdiyse. İkisini
/// birleştirmek, kod girmemiş kullanıcıda da gereksiz bir istek atmak
/// ve iki ayrı hata yolunu tek `nil`'e sıkıştırmak olurdu.
///
/// ⚠️ Ağ hatası **sessiz**: panel erişilemezse son bilinen yapılandırma
/// kullanılır. Bayinin müşterisi, panel bakımdayken markasız bir uygulama
/// görmemeli.
public actor PanelResellerConfigService: ResellerConfigProviding {

    private let endpoint: PanelEndpoint
    private let httpClient: HTTPClient
    private let store: UserDefaults

    private static let codeKey = "panel.resellerCode"
    private static let configKey = "panel.resellerConfig"

    public init(
        endpoint: PanelEndpoint = PanelEndpoint(),
        httpClient: HTTPClient? = nil,
        store: UserDefaults = .standard
    ) {
        self.endpoint = endpoint
        // Kullanıcı kodu girip bekliyor; uzun yeniden denemeler ekranı dondurur.
        self.httpClient = httpClient ?? URLSessionHTTPClient(retryPolicy: .single)
        self.store = store
    }

    // MARK: - Kod

    public func savedCode() async -> String? {
        let code = store.string(forKey: Self.codeKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (code?.isEmpty == false) ? code : nil
    }

    public func save(code: String?) async {
        guard let code, let normalized = ResellerConfig.normalizeCode(code) else {
            // Kod silindi: markalama da gitmeli, aksi hâlde eski bayinin
            // rengi ve duyurusu ekranda asılı kalır.
            store.removeObject(forKey: Self.codeKey)
            store.removeObject(forKey: Self.configKey)
            return
        }
        store.set(normalized, forKey: Self.codeKey)
    }

    // MARK: - Yapılandırma

    public func fetch(code: String) async -> ResellerConfig? {
        guard let normalized = ResellerConfig.normalizeCode(code) else { return nil }

        do {
            let data = try await httpClient.get(
                endpoint.resellerConfig(code: normalized),
                headers: [:]
            )
            let dto = try Self.decode(data)
            persist(dto)
            Log.network.info("Bayi yapılandırması alındı")
            return dto.toDomain()
        } catch {
            // Kod yanlışsa da ağ yoksa da buraya düşülür; ayrım yapılmıyor
            // çünkü kullanıcıya söylenecek şey aynı: "kod doğrulanamadı".
            Log.network.info("Bayi yapılandırması alınamadı")
            return nil
        }
    }

    public func cached() async -> ResellerConfig? {
        guard let data = store.data(forKey: Self.configKey),
              let dto = try? JSONDecoder().decode(ResellerConfigDTO.self, from: data)
        else { return nil }
        return dto.toDomain()
    }

    private func persist(_ dto: ResellerConfigDTO) {
        guard let data = try? JSONEncoder().encode(dto) else { return }
        store.set(data, forKey: Self.configKey)
    }

    static func decode(_ data: Data) throws -> ResellerConfigDTO {
        let decoder = JSONDecoder()

        // Panel `{success, config:{…}}` sarmalıyor. Başarısızlık durumunda
        // `success:false` ve `error` döner — o hâlde config yoktur.
        if let envelope = try? decoder.decode(ResellerEnvelope.self, from: data),
           let config = envelope.config {
            return config
        }
        throw AppError.invalidResponse(reason: "Bayi yapılandırması okunamadı")
    }
}

private struct ResellerEnvelope: Decodable {
    let config: ResellerConfigDTO?
}

/// Panel cevabının aktarım tipi.
///
/// `@Lenient`: panel sürümleri arasında `true` / `"1"` / `1` karışıyor;
/// tek alan yüzünden bayinin tüm markası kaybolmamalı.
struct ResellerConfigDTO: Codable {

    @Lenient var appName: String?
    @Lenient var logoUrl: String?
    @Lenient var announcement: String?
    @Lenient var maintenanceMode: Bool?
    @Lenient var whatsapp: String?
    @Lenient var telegram: String?
    @Lenient var contactEmail: String?

    /// ⚠️ Panelde bu alan yoksa (migration öncesi sunucu) **açık** kabul
    /// edilir. `false` varsaymak, sunucusu güncellenmemiş her bayinin
    /// uygulamasını bir anda kilitlerdi.
    @Lenient var platformIosEnabled: Bool?

    var theme: ThemeDTO?
    var dns: [DNSEntryDTO]?

    struct ThemeDTO: Codable {
        @Lenient var primaryColor: String?

        enum CodingKeys: String, CodingKey {
            case primaryColor = "primary_color"
        }
    }

    struct DNSEntryDTO: Codable {
        @Lenient var code: String?
        @Lenient var name: String?
        @Lenient var baseUrl: String?

        enum CodingKeys: String, CodingKey {
            case code, name
            case baseUrl = "base_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case theme, dns, announcement, whatsapp, telegram
        case appName = "app_name"
        case logoUrl = "logo_url"
        case maintenanceMode = "maintenance_mode"
        case contactEmail = "contact_email"
        case platformIosEnabled = "platform_ios_enabled"
    }

    func toDomain() -> ResellerConfig {
        ResellerConfig(
            appName: appName?.nilIfBlank,
            logoURL: logoUrl?.nilIfBlank.flatMap { URL(string: $0) },
            primaryColorHex: theme?.primaryColor?.nilIfBlank,
            announcement: announcement?.nilIfBlank,
            isUnderMaintenance: maintenanceMode == true,
            isIOSEnabled: platformIosEnabled ?? true,
            servers: (dns ?? []).compactMap { entry in
                // Adresi olmayan satır listede yer kaplar ama seçilince
                // hiçbir şey yapmaz — baştan elenir.
                guard let raw = entry.baseUrl?.nilIfBlank,
                      let url = URL(string: raw)
                else { return nil }

                return ResellerServer(
                    code: entry.code ?? "",
                    name: entry.name ?? "",
                    baseURL: url
                )
            },
            contact: ContactChannels(
                whatsAppURL: whatsapp?.nilIfBlank.flatMap { URL(string: $0) },
                telegramURL: telegram?.nilIfBlank.flatMap { URL(string: $0) },
                // Panel bayi için ayrı bir web sitesi alanı tutmuyor;
                // e-posta bağlantısı destek kanalı olarak kullanılır.
                websiteURL: contactEmail?.nilIfBlank.flatMap { URL(string: "mailto:\($0)") }
            )
        )
    }
}

extension String {
    /// Panel boş alanları `""` olarak gönderiyor; `nil` ile aynı anlama gelir.
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
