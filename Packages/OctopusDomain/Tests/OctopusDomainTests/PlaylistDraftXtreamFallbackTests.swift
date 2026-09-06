import XCTest
@testable import OctopusDomain

/// M3U bağlantısının Xtream'e çevrilmesi ve **geri düşüşü**.
final class PlaylistDraftXtreamFallbackTests: XCTestCase {

    private let id = Playlist.ID("p1")
    private let now = Date(timeIntervalSince1970: 0)

    private func draft(_ url: String) -> PlaylistDraft {
        PlaylistDraft(name: "", kind: .m3u(url: url, epgURL: ""))
    }

    private let xtreamLink = "http://panel.example.com:8080/get.php?username=abc&password=xyz&type=m3u_plus"

    func testKimlikTasiyanBaglantiXtreamKurulur() throws {
        let result = try draft(xtreamLink).build(id: id, createdAt: now)
        guard case .xtream(let host, let username) = result.playlist.kind else {
            return XCTFail("Xtream bekleniyordu, gelen: \(result.playlist.kind)")
        }
        XCTAssertEqual(host.absoluteString, "http://panel.example.com:8080")
        XCTAssertEqual(username, "abc")
        XCTAssertEqual(result.password, "xyz")
    }

    /// ⚠️ Geri düşüş yolu: bazı paneller `get.php` verir ama
    /// `player_api.php` ucunu kapatır. O hesapta dönüştürme tek yol
    /// sayılırsa çalışan kaynak kurulamaz hâle geliyordu.
    func testDonusturmeKapaliykenDuzM3UKalir() throws {
        let result = try draft(xtreamLink).build(
            id: id,
            createdAt: now,
            convertingXtreamLinks: false
        )
        guard case .m3u(let url) = result.playlist.kind else {
            return XCTFail("M3U bekleniyordu, gelen: \(result.playlist.kind)")
        }
        XCTAssertEqual(url.absoluteString, xtreamLink)
        XCTAssertNil(result.password, "M3U kaynağında parola saklanmamalı")
    }

    /// Kimlik taşımayan adres iki durumda da M3U kalmalı — bayrağın
    /// sıradan listelere dokunmadığı garanti altında.
    func testSiradanListeHerIkiDurumdaDaM3U() throws {
        for converting in [true, false] {
            let result = try draft("https://liste.example.com/kanallar.m3u")
                .build(id: id, createdAt: now, convertingXtreamLinks: converting)
            guard case .m3u = result.playlist.kind else {
                return XCTFail("M3U bekleniyordu (converting=\(converting))")
            }
        }
    }
}
