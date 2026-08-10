import Foundation

/// Bayi kodu karşılığında panelden gelen yapılandırma.
///
/// ## Global yapılandırmadan farkı
/// `RemoteAppConfig` **tüm** kurulumlar için ortaktır (uygulama sürümü,
/// bakım modu, genel duyuru). Bu tip ise **tek bir bayiye** aittir:
/// onun markası, kendi duyurusu, kendi sunucu listesi.
///
/// Öncelik her zaman bayidedir: bir bayi kendi rengini ayarladıysa
/// global tema onu ezmemeli. Birleştirme `RemoteAppConfig.applying(_:)`
/// içinde yapılır.
///
/// ⚠️ Bayi kodu bir sır **değildir** — müşteriye WhatsApp'tan gönderilen
/// 4 haneli bir koddur ve yalnızca markalama/sunucu listesi getirir.
/// Hesap bilgisi taşımaz; o iş aktivasyon kodunun (`ActivationRedeeming`).
public struct ResellerConfig: Equatable, Sendable {

    /// Uygulamanın bu bayide görünecek adı.
    public let appName: String?
    public let logoURL: URL?

    /// Bayinin seçtiği marka rengi, `#RRGGBB`.
    public let primaryColorHex: String?

    /// Yalnızca bu bayinin müşterilerine gösterilen duyuru.
    public let announcement: String?

    /// Bayi kendi hesabını bakıma aldı.
    public let isUnderMaintenance: Bool

    /// ⚠️ iOS bu bayide **kapalı** olabilir: pek çok bayi App Store
    /// onayı çıkana kadar yalnızca Android dağıtıyor. Kapalıyken
    /// uygulama içeriğe hiç girmemeli — aksi hâlde bayinin hazır
    /// olmadığı bir kanaldan destek talebi almasına yol açar.
    public let isIOSEnabled: Bool

    /// Bayinin sunucu (DNS) listesi.
    ///
    /// Kaynak eklerken kullanıcıya adres yazdırmak yerine bu liste
    /// sunulur — IPTV'de yanlış yazılan sunucu adresi en sık destek sebebi.
    public let servers: [ResellerServer]

    public let contact: ContactChannels

    public init(
        appName: String? = nil,
        logoURL: URL? = nil,
        primaryColorHex: String? = nil,
        announcement: String? = nil,
        isUnderMaintenance: Bool = false,
        isIOSEnabled: Bool = true,
        servers: [ResellerServer] = [],
        contact: ContactChannels = .empty
    ) {
        self.appName = appName
        self.logoURL = logoURL
        self.primaryColorHex = primaryColorHex
        self.announcement = announcement
        self.isUnderMaintenance = isUnderMaintenance
        self.isIOSEnabled = isIOSEnabled
        self.servers = servers
        self.contact = contact
    }
}

/// Bayinin tanımladığı bir sunucu girişi.
public struct ResellerServer: Equatable, Sendable, Identifiable, Hashable {

    /// Panelde tanımlı kısa kod (ör. "TR1"). Kimlik olarak da kullanılır.
    public let code: String
    public let name: String
    public let baseURL: URL

    /// ⚠️ Kod boş olabilir (panelde zorunlu değil); o durumda adres
    /// kimlik olur. Aksi hâlde kodsuz iki sunucu listede birleşirdi.
    public var id: String { code.isEmpty ? baseURL.absoluteString : code }

    /// Kullanıcıya gösterilecek etiket.
    public var displayName: String {
        if !name.isEmpty { return name }
        if !code.isEmpty { return code }
        return baseURL.host ?? baseURL.absoluteString
    }

    public init(code: String, name: String, baseURL: URL) {
        self.code = code
        self.name = name
        self.baseURL = baseURL
    }
}

/// Bayi kodunu çözer ve yapılandırmayı getirir.
public protocol ResellerConfigProviding: Sendable {

    /// Kodu panele sorar. Kod geçersizse `nil` döner (hata fırlatmaz:
    /// kullanıcı yanlış kod yazmış olabilir, bu bir arıza değil).
    func fetch(code: String) async -> ResellerConfig?

    /// Kayıtlı bayi kodunun yapılandırması — ağa çıkmadan.
    func cached() async -> ResellerConfig?

    /// Kullanıcının girdiği kod. Kod yoksa `nil`.
    func savedCode() async -> String?

    /// Kodu kaydeder (boş dizgi kaydı siler).
    func save(code: String?) async
}

extension ResellerConfig {

    /// Bayi kodunu ağa gönderilecek hâle getirir.
    ///
    /// ⚠️ Aktivasyon kodundan farklı olarak burada **büyük/küçük harf
    /// dönüşümü de yapılmaz**: panel eşleştirmeyi kendi tarafında
    /// harf duyarsız yapıyor (`LOWER(TRIM(d.code))`), bizim ayrıca
    /// dönüştürmemiz yalnızca yeni bir hata kaynağı olurdu.
    public static func normalizeCode(_ raw: String) -> String? {
        var text = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")

        guard !text.isEmpty else { return nil }

        // ⚠️ Bayiler müşteriye kodu değil **bağlantıyı** gönderiyor:
        // `https://octopusplayer.com/b/8811`. Kullanıcı da doğal olarak
        // bağlantının tamamını yapıştırıyor. Bunu reddetmek "kod bulunamadı"
        // demek olurdu — oysa kod tam orada, yolun sonunda.
        if text.contains("/") {
            // Çapa ve sorgu atılır: paylaşım bağlantıları izleme parametresi
            // taşıyabiliyor ve `8811?utm=whatsapp` diye bir kod yok.
            if let anchor = text.firstIndex(of: "#") { text = String(text[..<anchor]) }
            if let query = text.firstIndex(of: "?") { text = String(text[..<query]) }

            // Sondaki eğik çizgi yaygın: `/b/8811/`
            if let last = text.split(separator: "/").last(where: { !$0.isEmpty }) {
                text = String(last)
            }
        }

        // Nokta kalmışsa elde kod değil bir alan adı var (ör. yalnızca
        // `octopusplayer.com` yapıştırılmış). Panele göndermenin anlamı yok.
        guard !text.contains(".") else { return nil }

        // Tek karakterlik girdi kazara dokunuştur; ağa çıkmaya değmez.
        guard text.count >= 2 else { return nil }
        return text
    }
}

extension RemoteAppConfig {

    /// Bayi yapılandırmasını global yapılandırmanın **üzerine** uygular.
    ///
    /// Kural basit: bayi bir şeyi tanımladıysa o kazanır. Tanımlamadıysa
    /// global değer korunur — bayi hiçbir şey ayarlamamış olsa bile
    /// uygulama markasız kalmaz.
    public func applying(_ reseller: ResellerConfig) -> RemoteAppConfig {
        var merged = self

        // ⚠️ Kapı sıralaması önemli: iOS kapalıysa bakım mesajı yerine
        // "bu platform kapalı" gösterilmeli, ikisi birden varsa daha
        // kısıtlayıcı olan kazanır.
        if !reseller.isIOSEnabled {
            merged.gate = .platformUnavailable
        } else if reseller.isUnderMaintenance, !gate.isBlocking {
            merged.gate = .maintenance(message: nil)
        }

        if let announcement = reseller.announcement.flatMap(Announcement.init(message:)) {
            merged.announcement = announcement
        }

        merged.branding = BrandConfiguration(
            primaryColorHex: reseller.primaryColorHex ?? branding.primaryColorHex,
            resellerName: reseller.appName ?? branding.resellerName,
            logoURL: reseller.logoURL ?? branding.logoURL
        )

        if reseller.contact.hasAny {
            merged.contact = reseller.contact
        }

        return merged
    }
}
