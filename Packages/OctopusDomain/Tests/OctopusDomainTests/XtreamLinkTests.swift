import XCTest
@testable import OctopusDomain

/// Xtream kimliği taşıyan M3U bağlantılarının tanınması.
///
/// ⚠️ Bu kural gerçek bir olaydan doğdu: panel `playlist_type: "m3u"`
/// gönderdi, adres ise bir Xtream `get.php` bağlantısıydı. M3U olarak
/// işlenince 250 MB'lık tek dosya inip 355 bin satır yazıldı — oysa aynı
/// hesap Xtream API'sinde sayfalı geliyor.
final class XtreamLinkTests: XCTestCase {

    private func url(_ text: String) throws -> URL {
        try XCTUnwrap(URL(string: text))
    }

    func test_recognizesGetPHPLink() throws {
        let credentials = XtreamLink.credentials(
            from: try url("http://sunucu.example.com:8080/get.php?username=abc&password=xyz&type=m3u_plus&output=ts")
        )

        XCTAssertEqual(credentials?.host.absoluteString, "http://sunucu.example.com:8080")
        XCTAssertEqual(credentials?.username, "abc")
        XCTAssertEqual(credentials?.password, "xyz")
    }

    func test_recognizesPlayerAPILink() throws {
        let credentials = XtreamLink.credentials(
            from: try url("https://panel.example.com/player_api.php?username=u&password=p")
        )

        XCTAssertEqual(credentials?.host.absoluteString, "https://panel.example.com")
        XCTAssertEqual(credentials?.username, "u")
    }

    /// ⚠️ Yalnızca yola bakmak yetmez: kimlik taşımayan bir `get.php`
    /// adresi Xtream sanılırsa kaynak hiç açılmayacak şekilde kurulurdu.
    func test_ignoresLinkWithoutCredentials() throws {
        XCTAssertNil(XtreamLink.credentials(from: try url("http://sunucu.example.com/get.php")))
        XCTAssertNil(
            XtreamLink.credentials(from: try url("http://sunucu.example.com/get.php?username=abc"))
        )
        XCTAssertNil(
            XtreamLink.credentials(
                from: try url("http://sunucu.example.com/get.php?username=&password=")
            )
        )
    }

    func test_ignoresPlainPlaylistFile() throws {
        XCTAssertNil(XtreamLink.credentials(from: try url("http://liste.example.com/kanallar.m3u")))
    }

    /// Elle M3U yapıştıran kullanıcı da aynı kazancı görmeli.
    func test_manualM3UDraftBecomesXtream() throws {
        let draft = PlaylistDraft(
            name: "",
            kind: .m3u(
                url: "http://sunucu.example.com:8080/get.php?username=abc&password=xyz&type=m3u_plus",
                epgURL: ""
            )
        )

        let (playlist, password) = try draft.build(id: Playlist.ID("1"), createdAt: Date())

        guard case .xtream(let host, let username) = playlist.kind else {
            return XCTFail("Xtream'e çevrilmeliydi")
        }
        XCTAssertEqual(host.absoluteString, "http://sunucu.example.com:8080")
        XCTAssertEqual(username, "abc")
        XCTAssertEqual(password, "xyz")
    }

    func test_plainM3UDraftStaysM3U() throws {
        let draft = PlaylistDraft(
            name: "Listem",
            kind: .m3u(url: "http://liste.example.com/kanallar.m3u", epgURL: "")
        )

        let (playlist, password) = try draft.build(id: Playlist.ID("1"), createdAt: Date())

        guard case .m3u = playlist.kind else { return XCTFail("M3U kalmalıydı") }
        XCTAssertNil(password)
    }
}
