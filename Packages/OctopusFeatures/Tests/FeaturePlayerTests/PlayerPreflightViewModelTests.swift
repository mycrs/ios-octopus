import XCTest
import OctopusDomain
@testable import FeaturePlayer

/// Adres maskeleme — ekran görüntüsü hesabı ele vermemeli.
///
/// ⚠️ Xtream adresleri kimlik bilgilerini **yolun içinde** taşır:
/// `http://sunucu:8080/kullanici/parola/12345.ts`
/// Bu, IPTV'ye özgü ve kolayca gözden kaçan bir sızıntı yolu.
final class PlayerPreflightMaskingTests: XCTestCase {

    private func mask(_ raw: String) throws -> String {
        let url = try XCTUnwrap(URL(string: raw))
        return PlayerPreflightViewModel.maskedURL(url)
    }

    func test_masksXtreamPathCredentials() throws {
        let masked = try mask("http://panel.example.com:8080/ahmet/gizliparola/12345.ts")

        XCTAssertFalse(masked.contains("ahmet"), "Kullanıcı adı görünmemeli")
        XCTAssertFalse(masked.contains("gizliparola"), "Parola görünmemeli")
        XCTAssertTrue(masked.contains("12345.ts"), "Akış kimliği kalmalı")
        XCTAssertTrue(masked.contains("panel.example.com"), "Sunucu görünmeli")
    }

    func test_masksQueryCredentials() throws {
        let masked = try mask(
            "http://panel.example.com/player_api.php?username=ahmet&password=gizli&action=x"
        )

        XCTAssertFalse(masked.contains("ahmet"))
        XCTAssertFalse(masked.contains("gizli"))
        XCTAssertTrue(masked.contains("action=x"), "Kimlik dışı alanlar kalmalı")
    }

    func test_keepsPlainURLReadable() throws {
        // M3U kaynaklarda adres genelde kimlik taşımaz; okunabilir kalmalı.
        let raw = "http://cdn.example.com/live/kanal.m3u8"
        XCTAssertEqual(try mask(raw), raw)
    }

    func test_shortPathIsNotMangled() throws {
        let raw = "http://example.com/akis.ts"
        XCTAssertEqual(try mask(raw), raw)
    }

    func test_maskingNeverLeaksOriginalCredentials() throws {
        // Biçimden bağımsız temel güvence.
        let cases = [
            "http://a.com:8080/user1/pass1/1.ts",
            "http://a.com:8080/user1/pass1/movie/1.mp4",
            "https://a.com/user1/pass1/series/1.mkv"
        ]

        for raw in cases {
            let masked = try mask(raw)
            XCTAssertFalse(masked.contains("pass1"), "Parola sızdı: \(raw) → \(masked)")
        }
    }
}
