import XCTest
@testable import OctopusDomain

/// Kartın **ne zaman** çıkacağı: jenerik akarken, bitişte değil.
final class NextEpisodePromptTests: XCTestCase {

    /// 40 dakikalık bölümün son 30 saniyesi — jenerik akıyor.
    func testJenerikBaslayincaKartCikar() {
        XCTAssertEqual(
            NextEpisodePrompt.countdown(currentSeconds: 2370, durationSeconds: 2400),
            30
        )
    }

    func testBolumOrtasindaKartCikmaz() {
        XCTAssertNil(
            NextEpisodePrompt.countdown(currentSeconds: 1200, durationSeconds: 2400)
        )
    }

    /// ⚠️ Bazı paneller VOD süresini bildirmiyor; eşik hesaplanamaz ve
    /// çağıran taraf bitişteki davranışa düşmeli.
    func testSureBilinmiyorsaKartCikmaz() {
        XCTAssertNil(
            NextEpisodePrompt.countdown(currentSeconds: 1200, durationSeconds: nil)
        )
    }

    /// Kısa içerikte 45 sn, sürenin dörtte biri eder.
    func testKisaIcerikteEsikUygulanmaz() {
        XCTAssertNil(
            NextEpisodePrompt.countdown(currentSeconds: 150, durationSeconds: 180)
        )
    }

    /// Kullanıcı geri sarınca kart kapanmalı.
    func testGeriSarincaKartKapanir() {
        XCTAssertNotNil(
            NextEpisodePrompt.countdown(currentSeconds: 2380, durationSeconds: 2400)
        )
        XCTAssertNil(
            NextEpisodePrompt.countdown(currentSeconds: 1000, durationSeconds: 2400)
        )
    }

    /// Bitişte ve sonrasında sayaç negatife düşmemeli.
    func testBitiseVarincaSayacUretilmez() {
        XCTAssertEqual(
            NextEpisodePrompt.countdown(currentSeconds: 2399.5, durationSeconds: 2400),
            1
        )
        XCTAssertNil(
            NextEpisodePrompt.countdown(currentSeconds: 2400, durationSeconds: 2400)
        )
        XCTAssertNil(
            NextEpisodePrompt.countdown(currentSeconds: 2405, durationSeconds: 2400)
        )
    }
}
