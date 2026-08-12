import XCTest
import OctopusDomain
@testable import OctopusData

/// Aktivasyon kodu: biçim denetimi, hata eşlemesi, cevap çözümleme.
final class PanelActivationTests: XCTestCase {

    private func json(_ text: String) -> Data { Data(text.utf8) }

    private func makeService(
        response: @escaping @Sendable () throws -> Data
    ) -> PanelActivationService {
        PanelActivationService(httpClient: StubHTTPClient { _ in try response() })
    }

    // MARK: - Kod normalizasyonu

    func test_onlyWhitespaceIsStripped() {
        // ⚠️ Harf büyüklüğü **korunur**: panel kodları büyük/küçük harfe
        // duyarlı olabilir ve çevirmek doğru kodu bozardı.
        XCTAssertEqual(PanelActivationService.normalizeCode("abc-123"), "abc-123")
        XCTAssertEqual(PanelActivationService.normalizeCode("  aBc 123  "), "aBc123")
    }

    func test_onlyEmptyInputIsRejectedWithoutNetwork() {
        XCTAssertNil(PanelActivationService.normalizeCode(""))
        XCTAssertNil(PanelActivationService.normalizeCode("a"), "Tek karakter kazara dokunuş")

        // Alışılmadık karakterler ve uzunluklar **panele bırakılır**:
        // hangi kodun geçerli olduğuna uygulama karar veremez.
        XCTAssertEqual(PanelActivationService.normalizeCode("KOD@123"), "KOD@123")
        XCTAssertNotNil(PanelActivationService.normalizeCode(String(repeating: "A", count: 41)))
    }

    /// ⚠️ Yalnızca **boş** girdi ağa çıkmadan elenir.
    ///
    /// Eskiden karakter süzgeci vardı ve "@@" gibi girdiler yerel olarak
    /// reddediliyordu; bu, panelin ürettiği ama bizim beklemediğimiz
    /// biçimdeki kodları da eliyordu. Geçerliliğe panel karar verir.
    func test_emptyCodeThrowsBeforeRequest() async {
        let box = LockedBox(0)
        let service = PanelActivationService(
            httpClient: StubHTTPClient { _ in
                box.set(box.get() + 1)
                return Data()
            }
        )

        do {
            _ = try await service.redeem(code: "   ")
            XCTFail("Boş kod reddedilmeliydi")
        } catch {
            XCTAssertEqual(error as? ActivationError, .invalidFormat)
            XCTAssertEqual(box.get(), 0, "Boş kod için ağa çıkılmamalı")
        }
    }

    // MARK: - Hata eşlemesi
    //
    // ⚠️ Panel hatayı HTTP 200 gövdesinde bildiriyor; durum koduna bakmak yetmez.

    func test_serverErrorsMapToDistinctCases() throws {
        let cases: [(String, ActivationError)] = [
            ("code_not_found", .notFound),
            ("code_inactive", .notFound),
            ("code_expired", .expired),
            ("code_already_used", .alreadyUsed),
            ("too_many_attempts", .tooManyAttempts),
            ("rate_limited_redeem", .rateLimited),
            ("invalid_code_format", .invalidFormat)
        ]

        for (serverCode, expected) in cases {
            XCTAssertThrowsError(
                try PanelActivationService.parse(json(#"{"error":"\#(serverCode)"}"#))
            ) { error in
                XCTAssertEqual(error as? ActivationError, expected, "Eşleşmedi: \(serverCode)")
            }
        }
    }

    func test_unknownServerErrorIsPreserved() {
        XCTAssertThrowsError(
            try PanelActivationService.parse(json(#"{"error":"kozmik_isin"}"#))
        ) { error in
            XCTAssertEqual(error as? ActivationError, .unknown("kozmik_isin"))
        }
    }

    func test_errorGuidanceDiffersByCase() {
        // Kullanıcıya "tekrar dene" ile "bayine başvur" farklı durumlarda söylenir.
        XCTAssertTrue(ActivationError.rateLimited.isWorthRetrying)
        XCTAssertFalse(ActivationError.expired.isWorthRetrying)
        XCTAssertTrue(ActivationError.expired.requiresResellerContact)
        XCTAssertTrue(ActivationError.alreadyUsed.requiresResellerContact)
        XCTAssertFalse(ActivationError.invalidFormat.requiresResellerContact)
    }

    // MARK: - Xtream sonucu

    func test_parsesXtreamActivation() throws {
        let result = try PanelActivationService.parse(json("""
            {"playlist_type":"xtream","display_name":"Ev Aboneliği",
             "customer_name":"Ali Veli","server_url":"panel.example.com:8080",
             "username":"kullanici","password":"gizli","playlist_protected":false}
            """))

        guard case .xtream(let host, let username) = result.kind else {
            return XCTFail("Xtream bekleniyordu")
        }
        // Panel adresi şemasız gönderebiliyor.
        XCTAssertEqual(host.absoluteString, "http://panel.example.com:8080")
        XCTAssertEqual(username, "kullanici")
        XCTAssertEqual(result.password, "gizli")
        XCTAssertEqual(result.displayName, "Ev Aboneliği")
        XCTAssertEqual(result.customerName, "Ali Veli")
    }

    func test_parsesM3UActivation() throws {
        let result = try PanelActivationService.parse(json("""
            {"playlist_type":"m3u","playlist_name":"Liste",
             "m3u_url":"http://liste.example.com/p.m3u"}
            """))

        guard case .m3u(let url) = result.kind else { return XCTFail("M3U bekleniyordu") }
        XCTAssertEqual(url.absoluteString, "http://liste.example.com/p.m3u")
        XCTAssertNil(result.password, "M3U kaynağında parola olmaz")
        XCTAssertEqual(result.displayName, "Liste")
    }

    /// Panelin **gerçekte** gönderdiği biçim: alanlar `playlist` nesnesinin içinde.
    ///
    /// ⚠️ Bu yapı canlı panelden alındı. Alanlar bir dönem yalnızca en üst
    /// seviyede aranıyordu; panel kodu kabul ettiği hâlde "Aktivasyon
    /// bilgileri eksik" hatası veriliyor ve kullanıcı kaynak ekleyemiyordu.
    /// Test bu yüzden var: yapı bir daha sessizce kaymasın.
    func test_parsesNestedPlaylistPayload() throws {
        let result = try PanelActivationService.parse(json("""
            {"success":true,
             "playlist":{"playlist_type":"m3u","playlist_name":"Liste",
                         "m3u_url":"http://ornek.example.com:8080/get.php?username=u&password=p&type=m3u_plus",
                         "playlist_protected":false,"playlist_pin":""},
             "theme":{"theme_key":"red_black","primary_color":"#E50914"}}
            """))

        // ⚠️ Panel "m3u" diyor ama adres Xtream kimliği taşıyor: kaynak
        // **Xtream** olarak kurulmalı. M3U olarak kurulunca tüm katalog
        // tek dosyada iniyordu (gerçekte 250 MB / 355 bin satır).
        guard case .xtream(let host, let username) = result.kind else {
            return XCTFail("Xtream'e çevrilmeliydi")
        }
        XCTAssertEqual(host.absoluteString, "http://ornek.example.com:8080")
        XCTAssertEqual(username, "u")
        XCTAssertEqual(result.password, "p", "Parola bağlantıdan alınmalı")
        XCTAssertEqual(result.displayName, "Liste")
        XCTAssertFalse(result.isProtected)
    }

    /// Kimlik taşımayan gerçek bir M3U bağlantısı M3U kalmalı.
    func test_plainNestedM3UStaysM3U() throws {
        let result = try PanelActivationService.parse(json("""
            {"success":true,
             "playlist":{"playlist_type":"m3u","playlist_name":"Liste",
                         "m3u_url":"http://liste.example.com/kanallar.m3u"}}
            """))

        guard case .m3u = result.kind else { return XCTFail("M3U bekleniyordu") }
        XCTAssertNil(result.password)
    }

    /// İç içe gelen Xtream bilgileri de okunmalı.
    func test_parsesNestedXtreamPayload() throws {
        let result = try PanelActivationService.parse(json("""
            {"success":true,
             "playlist":{"playlist_type":"xtream","display_name":"Ev",
                         "server_url":"panel.example.com:8080",
                         "username":"kullanici","password":"parola"}}
            """))

        guard case .xtream(let host, let username) = result.kind else {
            return XCTFail("Xtream bekleniyordu")
        }
        XCTAssertEqual(host.absoluteString, "http://panel.example.com:8080")
        XCTAssertEqual(username, "kullanici")
        XCTAssertEqual(result.password, "parola")
        XCTAssertEqual(result.displayName, "Ev")
    }

    func test_kindIsInferredWhenTypeMissing() throws {
        // Bazı paneller tür alanını göndermiyor, yalnızca dolu alanları veriyor.
        let xtream = try PanelActivationService.parse(json("""
            {"server_url":"http://panel.example.com","username":"u","password":"p"}
            """))
        XCTAssertTrue(xtream.kind.isXtream)

        let m3u = try PanelActivationService.parse(json("""
            {"m3u_url":"http://liste.example.com/p.m3u"}
            """))
        XCTAssertFalse(m3u.kind.isXtream)
    }

    func test_missingCredentialsAreRejected() {
        // Kullanıcı adı olmadan Xtream kaynağı kurulamaz.
        XCTAssertThrowsError(
            try PanelActivationService.parse(json(#"{"playlist_type":"xtream","server_url":"http://x.com"}"#))
        )
        XCTAssertThrowsError(
            try PanelActivationService.parse(json("{}"))
        )
    }

    func test_defaultNameWhenPanelSendsNone() throws {
        let result = try PanelActivationService.parse(json("""
            {"m3u_url":"http://liste.example.com/p.m3u"}
            """))
        XCTAssertEqual(result.displayName, "Listem")
    }

    // MARK: - Bayi markası

    func test_resellerBrandingIsCarried() throws {
        let result = try PanelActivationService.parse(json("""
            {"m3u_url":"http://liste.example.com/p.m3u",
             "reseller_name":"Bayi A","reseller_primary_color":"#00E676",
             "reseller_logo_url":"https://cdn.example.com/logo.png"}
            """))

        XCTAssertEqual(result.branding?.resellerName, "Bayi A")
        XCTAssertEqual(result.branding?.effectiveColorHex, "#00E676")
        XCTAssertNotNil(result.branding?.logoURL)
    }

    /// Canlı aktivasyon cevabında bayi adı ve logosu üst seviyede değil,
    /// `reseller_config` içinde geliyor. Bu sözleşme desteklenmezse kodla
    /// giriş başarılı olsa bile arayüz varsayılan marka ile açılır.
    func test_nestedResellerConfigBrandingIsCarried() throws {
        let result = try PanelActivationService.parse(json("""
            {"success":true,
             "playlist":{"playlist_type":"m3u","playlist_name":"Liste",
                         "m3u_url":"http://ornek.example.com/list.m3u"},
             "theme":{"primary_color":"#2196F3"},
             "reseller_config":{"app_name":"Qruze Player",
                                  "logo_url":"https://cdn.example.com/qruze.png",
                                  "theme":{"primary_color":"#AA22CC"}}}
            """))

        XCTAssertEqual(result.branding?.resellerName, "Qruze Player")
        XCTAssertEqual(result.branding?.effectiveColorHex, "#2196F3")
        XCTAssertEqual(
            result.branding?.logoURL?.absoluteString,
            "https://cdn.example.com/qruze.png"
        )
    }

    func test_noBrandingWhenPanelSendsNone() throws {
        let result = try PanelActivationService.parse(json("""
            {"m3u_url":"http://liste.example.com/p.m3u"}
            """))
        XCTAssertNil(result.branding)
    }

    // MARK: - Uçtan uca

    func test_successfulRedeemThroughService() async throws {
        let service = makeService {
            self.json("""
                {"playlist_type":"xtream","server_url":"http://panel.example.com",
                 "username":"u","password":"p","display_name":"Test"}
                """)
        }

        let result = try await service.redeem(code: "abc-123")
        XCTAssertEqual(result.displayName, "Test")
        XCTAssertTrue(result.kind.isXtream)
    }

    func test_unauthorizedResponseBecomesNotFound() async {
        // Panel geçersiz kodu 401 ile de bildirebiliyor.
        let service = makeService { throw AppError.unauthorized }

        do {
            _ = try await service.redeem(code: "ABC-123")
            XCTFail("Hata bekleniyordu")
        } catch {
            XCTAssertEqual(error as? ActivationError, .notFound)
        }
    }
}
