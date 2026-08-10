import Foundation

/// Bayi paneli uç noktaları.
///
/// Taban adres tek yerden yönetilir: bayi paketlerinde derleme sırasında
/// değiştirilebilmesi gerekiyor.
public struct PanelEndpoint: Sendable {

    /// Varsayılan panel adresi.
    ///
    /// Not: Bu adres uygulama paketinde zaten görünür olacağı için gizli
    /// bilgi değildir. Yine de tek noktada tutulur ki bayi dağıtımlarında
    /// tek satır değişsin.
    public static let defaultBaseURL = URL(string: "https://octopusdocumentary.com")!

    public let baseURL: URL

    public init(baseURL: URL = PanelEndpoint.defaultBaseURL) {
        self.baseURL = Self.normalized(baseURL)
    }

    public var appConfig: URL { path("/api/app-config") }
    public var activationRedeem: URL { path("/api/activation/redeem") }
    public var dnsList: URL { path("/api/dns-list") }

    /// Bayi yapılandırması — 4 haneli bayi kodu ya da gizli giriş anahtarı.
    ///
    /// ⚠️ Kod yol bileşenine yazılıyor, bu yüzden **yüzde kodlaması şart**:
    /// panel kodlarında `/` görülmese de kullanıcı yanlış bir şey
    /// yapıştırdığında adres bozulur ve istek başka bir uca gider.
    public func resellerConfig(code: String) -> URL {
        let encoded = code.addingPercentEncoding(
            withAllowedCharacters: .alphanumerics
        ) ?? code
        return path("/api/public/reseller-config/\(encoded)")
    }

    private func path(_ component: String) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = component
        return components?.url ?? baseURL
    }

    /// Sondaki eğik çizgiler temizlenir; aksi halde adresler çift eğik
    /// çizgiyle kurulup bazı sunucularda 404 döner.
    static func normalized(_ url: URL) -> URL {
        var text = url.absoluteString.trimmingCharacters(in: .whitespaces)
        while text.hasSuffix("/") { text.removeLast() }
        return URL(string: text) ?? url
    }
}
