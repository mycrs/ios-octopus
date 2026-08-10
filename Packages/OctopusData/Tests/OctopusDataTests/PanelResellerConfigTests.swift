import XCTest
import OctopusDomain
@testable import OctopusData

/// Panel ile uygulama arasındaki **sözleşme** testi.
///
/// Buradaki JSON, çalışan panelden (`/api/public/reseller-config/...`)
/// alınmış gerçek bir yanıttır — elle uydurulmadı. Panel bir alanın adını
/// değiştirdiğinde bu test kırmızıya döner; aksi hâlde uygulama sessizce
/// markasız açılır ve sebebi haftalarca fark edilmez.
final class PanelResellerConfigTests: XCTestCase {

    /// Gerçek panel yanıtı (bayi kodu `TR1` ile alındı).
    private let liveResponse = """
    {"success":true,"config":{
      "app_name":"My Reseller App","logo_url":"",
      "whatsapp":"https://wa.me/123","telegram":"https://t.me/test",
      "instagram":"","contact_email":"","announcement":"Test duyuru",
      "announcement_pc":"","maintenance_mode":false,"force_update":false,
      "minimum_version":"","platform_pc_enabled":true,
      "platform_mobile_enabled":true,"platform_ios_enabled":true,
      "dns":[{"code":"TR1","name":"Turk DNS","base_url":"http://dns1.test.com:8080"}],
      "theme":{"theme_key":"red_black","primary_color":"#E50914"},
      "home_theme":{"home_theme_key":"classic_dock"}
    }}
    """

    private func decode(_ json: String) throws -> ResellerConfig {
        let data = Data(json.utf8)
        return try PanelResellerConfigService.decode(data).toDomain()
    }

    // MARK: - Gerçek yanıt

    func test_decodesLivePanelResponse() throws {
        let config = try decode(liveResponse)

        XCTAssertEqual(config.appName, "My Reseller App")
        XCTAssertEqual(config.announcement, "Test duyuru")
        XCTAssertFalse(config.isUnderMaintenance)
        XCTAssertTrue(config.isIOSEnabled)
    }

    /// Sunucu listesi bayi kodunun asıl kazancı — bozulursa kullanıcı
    /// adresi yine elle yazmak zorunda kalır.
    func test_decodesServerList() throws {
        let config = try decode(liveResponse)

        XCTAssertEqual(config.servers.count, 1)
        XCTAssertEqual(config.servers.first?.code, "TR1")
        XCTAssertEqual(config.servers.first?.displayName, "Turk DNS")
        XCTAssertEqual(
            config.servers.first?.baseURL.absoluteString,
            "http://dns1.test.com:8080"
        )
    }

    func test_decodesContactChannels() throws {
        let config = try decode(liveResponse)

        XCTAssertEqual(config.contact.whatsAppURL?.absoluteString, "https://wa.me/123")
        XCTAssertEqual(config.contact.telegramURL?.absoluteString, "https://t.me/test")
    }

    /// ⚠️ Panel boş alanları `""` gönderiyor. `nil`'e çevrilmezse
    /// "logosu var ama boş" durumuna düşülür ve arayüz boş bir kutu çizer.
    func test_blankFieldsBecomeNil() throws {
        let config = try decode(liveResponse)

        XCTAssertNil(config.logoURL, "logo_url boş dizgi")
    }

    // MARK: - Panel varsayılan kırmızısı

    /// ⚠️ Panel renk seçilmemişken de `#E50914` (kendi kırmızısı) gönderiyor.
    /// Ham hâli uygulanırsa her bayi kırmızı olur ve uygulamanın kimliği
    /// kaybolur. `effectiveColorHex` bu tonu eler.
    func test_panelDefaultRedIsIgnoredAsBrandColor() throws {
        let config = try decode(liveResponse)
        XCTAssertEqual(config.primaryColorHex, "#E50914", "Ham değer korunur")

        let branding = BrandConfiguration(
            primaryColorHex: config.primaryColorHex,
            resellerName: config.appName,
            logoURL: config.logoURL
        )
        XCTAssertNil(
            branding.effectiveColorHex,
            "Panel varsayılan kırmızısı marka rengi sayılmamalı"
        )
    }

    func test_realBrandColourSurvives() throws {
        let json = liveResponse.replacingOccurrences(of: "#E50914", with: "#22AA33")
        let config = try decode(json)

        let branding = BrandConfiguration(
            primaryColorHex: config.primaryColorHex,
            resellerName: nil,
            logoURL: nil
        )
        XCTAssertEqual(branding.effectiveColorHex, "#22AA33")
    }

    // MARK: - iOS bayrağı

    func test_iosDisabledIsRead() throws {
        let json = liveResponse.replacingOccurrences(
            of: "\"platform_ios_enabled\":true",
            with: "\"platform_ios_enabled\":false"
        )
        XCTAssertFalse(try decode(json).isIOSEnabled)
    }

    /// ⚠️ Sunucusu güncellenmemiş panelde alan **yok**. `false` varsaymak
    /// tüm bu bayilerin uygulamasını bir anda kilitlerdi.
    func test_missingIOSFlagDefaultsToEnabled() throws {
        let json = liveResponse.replacingOccurrences(
            of: "\"platform_ios_enabled\":true,",
            with: ""
        )
        XCTAssertTrue(try decode(json).isIOSEnabled)
    }

    // MARK: - Bozuk veri

    /// Adres taşımayan DNS satırı listede yer kaplar ama seçilince hiçbir
    /// şey yapmaz — baştan elenmeli.
    func test_serverWithoutURLIsDropped() throws {
        let json = liveResponse.replacingOccurrences(
            of: "\"base_url\":\"http://dns1.test.com:8080\"",
            with: "\"base_url\":\"\""
        )
        XCTAssertTrue(try decode(json).servers.isEmpty)
    }

    func test_failureResponseThrows() {
        let json = """
        {"success":false,"reseller_valid":false,"error":"Bayi bulunamadı"}
        """
        XCTAssertThrowsError(try decode(json))
    }
}
