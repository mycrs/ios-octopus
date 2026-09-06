import XCTest
@testable import OctopusDomain

final class HighEfficiencyHintTests: XCTestCase {

    func testPanellerinTipikAdlandirmalariYakalanir() {
        for title in [
            "TR: TRT 1 UHD",
            "4K | Sinema",
            "Movie HEVC",
            "Belgesel H265",
            "Doğa h.265",
            "Spor 2160p"
        ] {
            XCTAssertTrue(
                HighEfficiencyHint.suggestsFallbackEngine(title: title),
                "yakalanmalıydı: \(title)"
            )
        }
    }

    /// ⚠️ Asıl risk yanlış pozitif: gereksiz yere VLC'ye giden kanal
    /// PiP ve AirPlay'i kaybeder.
    func testSiradanKanallarAVPlayerdaKalir() {
        for title in [
            "TRT 1 HD",
            "Kanal D FHD",
            "24 Kanal",          // "4k" içerir ama kelime değil
            "Guhdar TV",         // "uhd" içerir ama kelime değil
            "Show TV"
        ] {
            XCTAssertFalse(
                HighEfficiencyHint.suggestsFallbackEngine(title: title),
                "yanlış yakalandı: \(title)"
            )
        }
    }

    /// İlk yazımda yalnızca ilk eşleşmeye bakılıyordu: baştaki sahte
    /// "4k" gerçek olanı gölgeliyor ve kanal ipucunu kaybediyordu.
    func testSahteEslesmeGercegiGolgelemez() {
        XCTAssertTrue(HighEfficiencyHint.suggestsFallbackEngine(title: "24 Kanal 4K"))
        XCTAssertTrue(HighEfficiencyHint.suggestsFallbackEngine(title: "Guhdar TV UHD"))
    }

    /// Çözünürlük eki alanın en yaygın yazımı; harf komşusu diye
    /// elenirse ipucu pratikte işe yaramaz.
    func testCozunurlukEkiKabulEdilirKelimeIcindeDegil() {
        XCTAssertTrue(HighEfficiencyHint.suggestsFallbackEngine(title: "Spor 2160p"))
        XCTAssertTrue(HighEfficiencyHint.suggestsFallbackEngine(title: "Film 2160i"))
        XCTAssertFalse(HighEfficiencyHint.suggestsFallbackEngine(title: "Test 2160pixel"))
    }
}
