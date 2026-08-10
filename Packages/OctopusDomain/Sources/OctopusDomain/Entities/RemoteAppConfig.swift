import Foundation

/// Bayi panelinden gelen uygulama yapılandırması.
///
/// Uygulama açılışında çekilir ve **çevrimdışı kullanım için saklanır** —
/// panel erişilemezse son bilinen yapılandırma kullanılır, uygulama
/// markasız veya kilitli açılmaz.
public struct RemoteAppConfig: Equatable, Sendable {

    public var announcement: Announcement?
    public var gate: ServiceGate
    public var branding: BrandConfiguration
    public var contact: ContactChannels

    /// Kullanıcı sunucu/kullanıcı/parola girerek kaynak ekleyebilir mi?
    ///
    /// ⚠️ Bayiler bunu kapatıyor: müşterinin yalnızca aktivasyon koduyla
    /// girmesini isterler, aksi hâlde panel bilgileri elden ele dolaşır.
    /// Panel bilgisi gelmeden **açık** varsayılır — yapılandırma
    /// çekilemediğinde kullanıcıyı uygulamaya hiç sokmamak olmaz.
    public var isXtreamLoginEnabled: Bool

    /// Yapılandırmanın çekildiği an — bayatlık denetimi için.
    public var fetchedAt: Date

    public init(
        announcement: Announcement? = nil,
        gate: ServiceGate = .open,
        branding: BrandConfiguration = .default,
        contact: ContactChannels = .empty,
        isXtreamLoginEnabled: Bool = true,
        fetchedAt: Date
    ) {
        self.announcement = announcement
        self.gate = gate
        self.branding = branding
        self.contact = contact
        self.isXtreamLoginEnabled = isXtreamLoginEnabled
        self.fetchedAt = fetchedAt
    }
}

/// Panelden yayınlanan duyuru.
public struct Announcement: Equatable, Sendable, Identifiable {

    /// Aynı duyurunun tekrar tekrar gösterilmemesi için kararlı kimlik.
    /// Metinden türetilir: panel yeni metin yayınlayınca kimlik de değişir.
    public var id: String { String(message.hashValue) }

    public let message: String

    public init?(message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.message = trimmed
    }
}

/// Uygulamanın kullanılabilirlik kapısı.
///
/// Panel bakım moduna aldığında veya zorunlu güncelleme yayınladığında
/// uygulama içeriğe erişimi keser. Bu, sunucu tarafı bir sorun sırasında
/// kullanıcının "uygulama bozuk" sanmasını önler.
public enum ServiceGate: Equatable, Sendable {
    case open
    case maintenance(message: String?)

    /// Bayi bu platformu (iOS) henüz açmadı.
    ///
    /// ⚠️ Bakımdan **ayrı** bir durum: bakım geçicidir ve "biraz sonra
    /// tekrar dene" demek doğrudur. Burada ise beklemenin faydası yok;
    /// kullanıcı bayisine başvurmalı. Aynı mesajı göstermek, kullanıcıyı
    /// saatlerce uygulamayı açıp kapatmaya iter.
    case platformUnavailable

    public var isBlocking: Bool {
        switch self {
        case .open: return false
        case .maintenance, .platformUnavailable: return true
        }
    }
}

/// Bayi markalaması.
public struct BrandConfiguration: Equatable, Sendable {

    /// Panelde tanımlı marka rengi, `#RRGGBB`. Boşsa uygulama varsayılanı.
    public let primaryColorHex: String?
    public let resellerName: String?
    public let logoURL: URL?

    public static let `default` = BrandConfiguration(
        primaryColorHex: nil,
        resellerName: nil,
        logoURL: nil
    )

    public init(primaryColorHex: String?, resellerName: String?, logoURL: URL?) {
        self.primaryColorHex = primaryColorHex
        self.resellerName = resellerName
        self.logoURL = logoURL
    }

    /// Panelden gelen rengin uygulanabilir olup olmadığı.
    ///
    /// ⚠️ Android sürümünden taşınan incelikli kural: eski panel varsayılanı
    /// **doygun kırmızı** ve bu, uygulamanın mavi kimliğini eziyor. Panel
    /// gerçekten renk seçmemişse kırmızı gönderiyor; bu durumda yok sayılır.
    public var effectiveColorHex: String? {
        guard let hex = primaryColorHex?.trimmingCharacters(in: .whitespaces),
              let rgb = Self.parseHex(hex),
              !Self.isPanelRedDefault(rgb)
        else { return nil }
        return hex.hasPrefix("#") ? hex : "#\(hex)"
    }

    static func parseHex(_ raw: String) -> (r: Double, g: Double, b: Double)? {
        var text = raw.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return (
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }

    /// Doygun kırmızı ailesi (yaklaşık 345°–18° ton) "renk seçilmemiş" sayılır.
    static func isPanelRedDefault(_ rgb: (r: Double, g: Double, b: Double)) -> Bool {
        let maxValue = max(rgb.r, rgb.g, rgb.b)
        let minValue = min(rgb.r, rgb.g, rgb.b)
        let delta = maxValue - minValue

        guard maxValue > 0 else { return false }
        let saturation = delta / maxValue
        guard saturation >= 0.45, maxValue >= 0.35 else { return false }
        guard rgb.r > rgb.g, rgb.r > rgb.b, abs(rgb.r - rgb.b) >= 0.08 else { return false }

        var hue: Double
        if delta == 0 {
            hue = 0
        } else if maxValue == rgb.r {
            hue = 60 * (((rgb.g - rgb.b) / delta).truncatingRemainder(dividingBy: 6))
        } else if maxValue == rgb.g {
            hue = 60 * (((rgb.b - rgb.r) / delta) + 2)
        } else {
            hue = 60 * (((rgb.r - rgb.g) / delta) + 4)
        }
        if hue < 0 { hue += 360 }

        return hue <= 18 || hue >= 345
    }
}

/// Bayinin destek kanalları.
public struct ContactChannels: Equatable, Sendable {

    public let whatsAppURL: URL?
    public let telegramURL: URL?
    public let websiteURL: URL?

    public static let empty = ContactChannels(
        whatsAppURL: nil,
        telegramURL: nil,
        websiteURL: nil
    )

    public init(whatsAppURL: URL?, telegramURL: URL?, websiteURL: URL?) {
        self.whatsAppURL = whatsAppURL
        self.telegramURL = telegramURL
        self.websiteURL = websiteURL
    }

    public var hasAny: Bool {
        whatsAppURL != nil || telegramURL != nil || websiteURL != nil
    }
}

/// Panel yapılandırmasını sağlar.
public protocol RemoteConfigProviding: Sendable {
    /// Ağdan tazeler; başarısızsa son saklanan yapılandırmayı döndürür.
    func refresh() async -> RemoteAppConfig?
    /// Yalnızca saklanan yapılandırma — ağa çıkmaz.
    func cached() async -> RemoteAppConfig?
}
