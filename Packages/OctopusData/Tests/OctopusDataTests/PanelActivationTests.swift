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

    func test_codeIsNormalizedBeforeSending() {
        // Kullanıcı küçük harf ve boşlukla yazabilir.
        XCTAssertEqual(PanelActivationService.normalizeCode("abc-123"), "ABC-123")
        XCTAssertEqual(PanelActivationService.normalizeCode("  abc 123  "), "ABC123")
    }

    func test_invalidCodeFormatsAreRejectedWithoutNetwork() {
        XCTAssertNil(PanelActivationService.normalizeCode(""))
        XCTAssertNil(PanelActivationService.normalizeCode("ab"), "Çok kısa")
        XCTAssertNil(PanelActivationService.normalizeCode("KOD@123"), "Geçersiz karakter")
        XCTAssertNil(PanelActivationService.normalizeCode(String(repeating: "A", count: 41)))
    }

    func test_invalidFormatThrowsBeforeRequest() async {
        let box = LockedBox(0)
        let service = PanelActivationService(
            httpClient: StubHTTPClient { _ in
                box.set(box.get() + 1)
                return Data()
            }
        )

        do {
            _ = try await service.redeem(code: "@@")
            XCTFail("Geçersiz biçim reddedilmeliydi")
        } catch {
            XCTAssertEqual(error as? ActivationError, .invalidFormat)
            XCTAssertEqual(box.get(), 0, "Bariz hatalı kod için ağa çıkılmamalı")
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
