import XCTest
@testable import OctopusDomain

/// Form verisinin doğrulanması ve entity'ye dönüşümü.
/// Saf mantık — simülatörsüz, Linux'ta koşar.
final class PlaylistDraftTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000)

    // MARK: - Adres normalizasyonu

    func test_schemelessHostGetsHTTP() throws {
        // Kullanıcı çoğu zaman şemasız yazar; IPTV panellerinin çoğu HTTPS sunmuyor.
        let draft = PlaylistDraft(
            name: "",
            kind: .xtream(host: "panel.example.com:8080", username: "u", password: "p")
        )
        let (playlist, _) = try draft.build(id: "p1", createdAt: now)

        guard case .xtream(let host, _) = playlist.kind else {
            return XCTFail("Xtream bekleniyordu")
        }
        XCTAssertEqual(host.absoluteString, "http://panel.example.com:8080")
    }

    func test_existingSchemeIsPreserved() throws {
        let draft = PlaylistDraft(
            name: "",
            kind: .xtream(host: "https://panel.example.com", username: "u", password: "p")
        )
        let (playlist, _) = try draft.build(id: "p1", createdAt: now)

        guard case .xtream(let host, _) = playlist.kind else {
            return XCTFail("Xtream bekleniyordu")
        }
        XCTAssertEqual(host.scheme, "https")
    }

    func test_trailingSlashesAreRemoved() throws {
        // Sondaki eğik çizgi akış adresinde çift eğik çizgiye yol açar.
        let draft = PlaylistDraft(
            name: "",
            kind: .xtream(host: "http://panel.example.com//", username: "u", password: "p")
        )
        let (playlist, _) = try draft.build(id: "p1", createdAt: now)

        guard case .xtream(let host, _) = playlist.kind else {
            return XCTFail("Xtream bekleniyordu")
        }
        XCTAssertEqual(host.absoluteString, "http://panel.example.com")
    }

    func test_invalidHostIsRejected() {
        for badHost in ["", "   ", "sadece-metin", "http://"] {
            let draft = PlaylistDraft(
                name: "",
                kind: .xtream(host: badHost, username: "u", password: "p")
            )
            XCTAssertThrowsError(try draft.build(id: "p1", createdAt: now)) { error in
                XCTAssertEqual(error as? PlaylistDraftError, .invalidHost, "Kabul edildi: '\(badHost)'")
            }
        }
    }

    func test_localhostIsAccepted() throws {
        // Geliştirme ve yerel sunucu senaryosu.
        let draft = PlaylistDraft(
            name: "",
            kind: .xtream(host: "localhost:8080", username: "u", password: "p")
        )
        XCTAssertNoThrow(try draft.build(id: "p1", createdAt: now))
    }

    // MARK: - Zorunlu alanlar

    func test_emptyCredentialsAreRejected() {
        let noUser = PlaylistDraft(
            name: "",
            kind: .xtream(host: "panel.example.com", username: "  ", password: "p")
        )
        XCTAssertThrowsError(try noUser.build(id: "p1", createdAt: now)) { error in
            XCTAssertEqual(error as? PlaylistDraftError, .emptyUsername)
        }

        let noPassword = PlaylistDraft(
            name: "",
            kind: .xtream(host: "panel.example.com", username: "u", password: "")
        )
        XCTAssertThrowsError(try noPassword.build(id: "p1", createdAt: now)) { error in
            XCTAssertEqual(error as? PlaylistDraftError, .emptyPassword)
        }
    }

    // MARK: - Parola entity'ye girmez

    func test_passwordIsReturnedSeparatelyNotStoredInEntity() throws {
        let draft = PlaylistDraft(
            name: "Hesabım",
            kind: .xtream(host: "panel.example.com", username: "kullanici", password: "gizli123")
        )
        let (playlist, password) = try draft.build(id: "p1", createdAt: now)

        XCTAssertEqual(password, "gizli123")
        // Entity'nin hiçbir alanında parola geçmemeli.
        XCTAssertFalse(String(describing: playlist).contains("gizli123"))
    }

    // MARK: - Ad üretimi

    func test_emptyNameFallsBackToHost() throws {
        let xtream = PlaylistDraft(
            name: "   ",
            kind: .xtream(host: "panel.example.com:8080", username: "u", password: "p")
        )
        let (playlist, _) = try xtream.build(id: "p1", createdAt: now)
        XCTAssertEqual(playlist.name, "panel.example.com")

        let m3u = PlaylistDraft(
            name: "",
            kind: .m3u(url: "http://liste.example.com/p.m3u", epgURL: "")
        )
        let (m3uPlaylist, _) = try m3u.build(id: "p2", createdAt: now)
        XCTAssertEqual(m3uPlaylist.name, "liste.example.com")
    }

    func test_providedNameWins() throws {
        let draft = PlaylistDraft(
            name: "  Ev Aboneliği  ",
            kind: .m3u(url: "http://liste.example.com/p.m3u", epgURL: "")
        )
        let (playlist, _) = try draft.build(id: "p1", createdAt: now)
        XCTAssertEqual(playlist.name, "Ev Aboneliği", "Baştaki/sondaki boşluk kırpılmalı")
    }

    // MARK: - M3U

    func test_m3uWithoutEPGHasNilEPGURL() throws {
        let draft = PlaylistDraft(
            name: "",
            kind: .m3u(url: "http://liste.example.com/p.m3u", epgURL: "   ")
        )
        let (playlist, password) = try draft.build(id: "p1", createdAt: now)

        XCTAssertNil(playlist.epgURL)
        XCTAssertNil(password, "M3U kaynağında parola yok")
    }

    func test_m3uWithEPGKeepsBothAddresses() throws {
        let draft = PlaylistDraft(
            name: "",
            kind: .m3u(
                url: "liste.example.com/p.m3u",
                epgURL: "epg.example.com/guide.xml"
            )
        )
        let (playlist, _) = try draft.build(id: "p1", createdAt: now)

        XCTAssertEqual(playlist.epgURL?.absoluteString, "http://epg.example.com/guide.xml")
        guard case .m3u(let url) = playlist.kind else { return XCTFail("M3U bekleniyordu") }
        XCTAssertEqual(url.absoluteString, "http://liste.example.com/p.m3u")
    }

    func test_invalidM3UURLIsRejected() {
        let draft = PlaylistDraft(name: "", kind: .m3u(url: "bozuk", epgURL: ""))
        XCTAssertThrowsError(try draft.build(id: "p1", createdAt: now)) { error in
            XCTAssertEqual(error as? PlaylistDraftError, .invalidURL)
        }
    }

    // MARK: - Yeni kaynak varsayılanları

    func test_newPlaylistIsNotActiveByDefault() throws {
        // Aktiflik ayrı bir karardır; kaydetme akışı bunu açıkça yapar.
        let draft = PlaylistDraft(
            name: "",
            kind: .m3u(url: "http://liste.example.com/p.m3u", epgURL: "")
        )
        let (playlist, _) = try draft.build(id: "p1", createdAt: now)

        XCTAssertFalse(playlist.isActive)
        XCTAssertNil(playlist.lastSyncedAt)
        XCTAssertEqual(playlist.createdAt, now)
    }
}
