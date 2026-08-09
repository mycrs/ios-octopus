import Foundation

/// Xtream kimlik bilgisi taşıyan M3U bağlantılarını çözer.
///
/// ## Neden gerekli?
/// Paneller "M3U bağlantısı" diye şuna benzer bir adres veriyor:
///
/// ```
/// http://sunucu.com:8080/get.php?username=abc&password=xyz&type=m3u_plus
/// ```
///
/// Bu aslında bir **Xtream** hesabıdır: adres, kullanıcı adı ve parola
/// bağlantının içinde. M3U olarak işlemek şu bedelleri getiriyor:
/// - Tüm katalog tek dosyada iniyor (bu kaynakta 250 MB, 355 bin satır),
/// - Kategori, dizi/sezon/bölüm ağacı ve EPG ayrı ayrı gelmiyor,
/// - Her güncellemede aynı devasa dosya baştan indiriliyor.
///
/// Xtream'de aynı içerik sayfalı JSON uçlarından, ihtiyaç oldukça geliyor.
/// Bu yüzden bağlantı tanınırsa kaynak **Xtream olarak** kurulur.
public enum XtreamLink {

    /// Bağlantıdan çıkarılan Xtream erişim bilgileri.
    public struct Credentials: Equatable, Sendable {
        public let host: URL
        public let username: String
        public let password: String

        public init(host: URL, username: String, password: String) {
            self.host = host
            self.username = username
            self.password = password
        }
    }

    /// Xtream olduğu anlaşılan uç noktalar.
    ///
    /// `get.php` liste indirme, `player_api.php` ise API ucudur; ikisi de
    /// aynı hesabı işaret eder.
    private static let knownPaths = ["get.php", "player_api.php", "xmltv.php"]

    /// Bağlantı bir Xtream hesabı taşıyor mu?
    ///
    /// ⚠️ Üç koşul da aranıyor: tanınan bir yol, **ve** dolu bir kullanıcı
    /// adı **ve** parola. Yalnızca yola bakmak, kimlik taşımayan bir
    /// `get.php` adresini yanlışlıkla Xtream sanmaya yol açardı.
    public static func credentials(from url: URL) -> Credentials? {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let scheme = components.scheme,
            let hostName = components.host
        else { return nil }

        let fileName = (components.path as NSString).lastPathComponent.lowercased()
        guard knownPaths.contains(fileName) else { return nil }

        let items = components.queryItems ?? []
        guard
            let username = value(of: "username", in: items), !username.isEmpty,
            let password = value(of: "password", in: items), !password.isEmpty
        else { return nil }

        // Sunucu adresi yol ve sorgu olmadan kurulur: Xtream API'si kendi
        // uçlarını bu köke ekliyor.
        var base = URLComponents()
        base.scheme = scheme
        base.host = hostName
        base.port = components.port

        guard let host = base.url else { return nil }
        return Credentials(host: host, username: username, password: password)
    }

    private static func value(of name: String, in items: [URLQueryItem]) -> String? {
        items.first { $0.name.lowercased() == name }?.value
    }
}
