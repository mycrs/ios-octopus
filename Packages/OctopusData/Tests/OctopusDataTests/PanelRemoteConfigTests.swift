import XCTest
import OctopusDomain
@testable import OctopusData

/// Panel yapılandırması: cevap biçimleri, çevrimdışı önbellek, dayanıklılık.
final class PanelRemoteConfigTests: XCTestCase {

    private var store: UserDefaults!
    private let suiteName = "panel.tests"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suiteName)
        store = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeService(
        response: @escaping @Sendable () throws -> Data
    ) -> PanelRemoteConfigService {
        PanelRemoteConfigService(
            httpClient: StubHTTPClient { _ in try response() },
            store: store,
            now: { Date(timeIntervalSince1970: 1_000) }
        )
    }

    private func json(_ text: String) -> Data { Data(text.utf8) }

    // MARK: - Cevap biçimleri

    func test_decodesEnvelopeForm() throws {
        // Panel `{success, config:{…}}` döndürebiliyor.
        let dto = try PanelRemoteConfigService.decode(json("""
            {"success":true,"config":{"announcement_enabled":true,
             "announcement_message":"Merhaba"}}
            """))
        XCTAssertEqual(dto.announcementMessage, "Merhaba")
    }

    func test_decodesFlatForm() throws {
        // Eski paneller düz nesne döndürüyor.
        let dto = try PanelRemoteConfigService.decode(json("""
            {"announcement_enabled":true,"announcement_message":"Merhaba"}
            """))
        XCTAssertEqual(dto.announcementMessage, "Merhaba")
    }

    func test_malformedResponseThrows() {
        XCTAssertThrowsError(try PanelRemoteConfigService.decode(json("<html>502</html>")))
    }

    // MARK: - Duyuru

    func test_announcementRequiresBothFlagAndMessage() async {
        // Bayrak kapalıysa metin olsa bile gösterilmez.
        let disabled = makeService {
            self.json(#"{"announcement_enabled":false,"announcement_message":"Gizli"}"#)
        }
        let disabledConfig = await disabled.refresh()
        XCTAssertNil(disabledConfig?.announcement)

        // Bayrak açık ama metin boşsa da gösterilmez.
        let empty = makeService {
            self.json(#"{"announcement_enabled":true,"announcement_message":"   "}"#)
        }
        let emptyConfig = await empty.refresh()
        XCTAssertNil(emptyConfig?.announcement)

        let valid = makeService {
            self.json(#"{"announcement_enabled":"1","announcement_message":"Bakım var"}"#)
        }
        let validConfig = await valid.refresh()
        XCTAssertEqual(validConfig?.announcement?.message, "Bakım var")
    }

    // MARK: - Bakım kapısı

    func test_maintenanceModeBlocksAccess() async {
        let service = makeService {
            self.json(#"{"maintenance_mode":true,"maintenance_message":"Yarın döneceğiz"}"#)
        }
        let config = await service.refresh()

        XCTAssertTrue(config?.gate.isBlocking ?? false)
        XCTAssertEqual(config?.gate, .maintenance(message: "Yarın döneceğiz"))
    }

    func test_defaultGateIsOpen() async {
        let service = makeService { self.json("{}") }
        let config = await service.refresh()
        XCTAssertEqual(config?.gate, .open)
    }

    // MARK: - Marka rengi

    func test_themeObjectTakesPrecedenceOverFlatField() async {
        // Yeni paneller rengi `theme` altında, eskiler düz alanda gönderiyor.
        // Not: iki diyezli sınırlayıcı şart — tek diyezli `#"…"#` biçimi,
        // içerikteki `"#00E676` dizisindeki `"#` ile erken kapanıyor.
        let service = makeService {
            self.json(##"{"primary_color":"#111111","theme":{"primary_color":"#00E676"}}"##)
        }
        let config = await service.refresh()
        XCTAssertEqual(config?.branding.effectiveColorHex, "#00E676")
    }

    func test_panelDefaultRedIsIgnoredEndToEnd() async {
        // Panel renk seçilmediğinde eski kırmızı varsayılanı gönderiyor;
        // bu, uygulamanın mavi kimliğini ezmemeli.
        let service = makeService { self.json(##"{"theme":{"primary_color":"#E50914"}}"##) }
        let config = await service.refresh()
        XCTAssertNil(config?.branding.effectiveColorHex)
    }

    // MARK: - Çevrimdışı dayanıklılık

    func test_networkFailureFallsBackToCache() async {
        // Önce başarılı çekim
        let online = makeService { self.json(#"{"announcement_enabled":true,"announcement_message":"Kayıtlı"}"#) }
        _ = await online.refresh()

        // Sonra ağ koptu
        let offline = makeService { throw AppError.network(reason: "kopuk") }
        let config = await offline.refresh()

        XCTAssertEqual(
            config?.announcement?.message,
            "Kayıtlı",
            "Panel erişilemezse son bilinen yapılandırma kullanılmalı"
        )
    }

    func test_noCacheAndNoNetworkReturnsNil() async {
        let service = makeService { throw AppError.network(reason: "kopuk") }
        let config = await service.refresh()
        XCTAssertNil(config, "Hiç veri yoksa nil dönmeli — uygulama varsayılanlarla açılır")
    }

    func test_cachedDoesNotTouchNetwork() async {
        let online = makeService { self.json(#"{"reseller_name":"Bayi A"}"#) }
        _ = await online.refresh()

        let box = LockedBox(0)
        let service = PanelRemoteConfigService(
            httpClient: StubHTTPClient { _ in
                box.set(box.get() + 1)
                return Data()
            },
            store: store,
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        let cached = await service.cached()
        XCTAssertEqual(cached?.branding.resellerName, "Bayi A")
        XCTAssertEqual(box.get(), 0, "cached() ağa çıkmamalı")
    }

    // MARK: - İletişim kanalları

    func test_contactChannelsAreParsed() async {
        let service = makeService {
            self.json("""
                {"whatsapp_url":"https://wa.me/905551112233",
                 "telegram_url":"https://t.me/kanal",
                 "website_url":"https://ornek.com"}
                """)
        }
        let config = await service.refresh()

        XCTAssertTrue(config?.contact.hasAny ?? false)
        XCTAssertEqual(config?.contact.whatsAppURL?.absoluteString, "https://wa.me/905551112233")
    }

    // MARK: - Uç nokta kurulumu

    func test_endpointsAreBuiltCorrectly() {
        let endpoint = PanelEndpoint(baseURL: URL(string: "https://panel.example.com/")!)
        XCTAssertEqual(endpoint.appConfig.absoluteString, "https://panel.example.com/api/app-config")
        XCTAssertEqual(
            endpoint.activationRedeem.absoluteString,
            "https://panel.example.com/api/activation/redeem"
        )
        XCTAssertEqual(endpoint.dnsList.absoluteString, "https://panel.example.com/api/dns-list")
    }

    func test_trailingSlashesAreStripped() {
        // Aksi halde adresler çift eğik çizgiyle kurulup 404 dönebiliyor.
        let endpoint = PanelEndpoint(baseURL: URL(string: "https://panel.example.com///")!)
        XCTAssertEqual(endpoint.appConfig.absoluteString, "https://panel.example.com/api/app-config")
    }
}
