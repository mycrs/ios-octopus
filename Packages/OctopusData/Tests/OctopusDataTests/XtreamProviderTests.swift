import XCTest
import OctopusDomain
@testable import OctopusData

/// Xtream sağlayıcısı. JSON örnekleri gerçek panel cevaplarının biçimindedir —
/// tip tutarsızlıkları dahil.
final class XtreamProviderTests: XCTestCase {

    private let baseURL = URL(string: "http://panel.example.com:8080")!

    private func makeProvider(
        liveFormat: XtreamContentProvider.LiveFormat = .hls,
        handler: @escaping @Sendable (URL) throws -> Data
    ) -> XtreamContentProvider {
        XtreamContentProvider(
            baseURL: baseURL,
            username: "kullanici",
            password: "parola",
            playlistID: "p1",
            httpClient: StubHTTPClient(handler: handler),
            liveFormat: liveFormat
        )
    }

    private func json(_ text: String) -> Data { Data(text.utf8) }

    // MARK: - Kimlik doğrulama

    func test_authenticate_parsesAccountInfo() async throws {
        let provider = makeProvider { _ in
            self.json("""
                {"user_info":{"username":"kullanici","status":"Active",
                "exp_date":"1893456000","is_trial":"0",
                "active_cons":"1","max_connections":"2","auth":1}}
                """)
        }

        let account = try await provider.authenticate()
        XCTAssertEqual(account.username, "kullanici")
        XCTAssertEqual(account.maxConnections, 2)
        XCTAssertEqual(account.activeConnections, 1)
        XCTAssertFalse(account.isTrial)
        XCTAssertEqual(account.expiresAt, Date(timeIntervalSince1970: 1_893_456_000))
    }

    func test_authenticate_rejectsAuthZeroDespiteHTTP200() async throws {
        // ⚠️ Panellerin çoğu geçersiz girişte de HTTP 200 döner.
        // Yalnızca durum koduna bakan bir istemci "giriş başarılı" sanırdı.
        let provider = makeProvider { _ in
            self.json(#"{"user_info":{"username":"","auth":0}}"#)
        }

        do {
            _ = try await provider.authenticate()
            XCTFail("auth:0 reddedilmeliydi")
        } catch {
            XCTAssertEqual(error as? AppError, .unauthorized)
        }
    }

    func test_authenticate_rejectsExpiredAccount() async throws {
        let provider = makeProvider { _ in
            self.json(#"{"user_info":{"username":"u","status":"Expired","auth":1}}"#)
        }

        do {
            _ = try await provider.authenticate()
            XCTFail("Süresi dolmuş hesap reddedilmeliydi")
        } catch {
            XCTAssertEqual(error as? AppError, .unauthorized)
        }
    }

    func test_authenticate_htmlErrorPageBecomesInvalidResponse() async throws {
        // Bazı paneller hata durumunda JSON yerine HTML döndürür.
        let provider = makeProvider { _ in self.json("<html><body>502</body></html>") }

        do {
            _ = try await provider.authenticate()
            XCTFail("HTML cevap hata vermeliydi")
        } catch let error as AppError {
            guard case .invalidResponse = error else {
                return XCTFail("Beklenen invalidResponse, gelen: \(error)")
            }
        }
    }

    // MARK: - Kanallar

    func test_fetchChannels_toleratesMixedTypes() async throws {
        // Aynı listede stream_id hem sayı hem dizgi; is_adult hem 0 hem "0".
        let provider = makeProvider { _ in
            self.json("""
                [
                 {"num":1,"name":"TRT 1","stream_id":12345,
                  "stream_icon":"http://logo.example.com/trt1.png",
                  "epg_channel_id":"trt1.tr","category_id":"5","is_adult":0},
                 {"num":"2","name":"Show TV","stream_id":"67890",
                  "stream_icon":"","epg_channel_id":null,
                  "category_id":5,"is_adult":"0"}
                ]
                """)
        }

        let channels = try await provider.fetchChannels(categoryID: nil)
        XCTAssertEqual(channels.count, 2, "Tip tutarsızlığı kayıt düşürmemeli")

        XCTAssertEqual(channels[0].name, "TRT 1")
        XCTAssertEqual(channels[0].streamKey, "12345")
        XCTAssertEqual(channels[0].epgChannelID, "trt1.tr")
        XCTAssertEqual(channels[0].number, 1)

        XCTAssertEqual(channels[1].streamKey, "67890")
        XCTAssertEqual(channels[1].number, 2)
        XCTAssertNil(channels[1].logoURL, "Boş logo adresi nil olmalı")
        XCTAssertNil(channels[1].epgChannelID)
    }

    func test_fetchChannels_skipsUnusableRecordsButKeepsRest() async throws {
        // stream_id olmadan yayın açılamaz; adsız kanal listelenemez.
        // Bunlar atlanmalı ama liste ayakta kalmalı.
        let provider = makeProvider { _ in
            self.json("""
                [
                 {"name":"Kimliksiz"},
                 {"stream_id":1,"name":"Geçerli"},
                 {"stream_id":2}
                ]
                """)
        }

        let channels = try await provider.fetchChannels(categoryID: nil)
        XCTAssertEqual(channels.map(\.name), ["Geçerli"])
    }

    func test_fetchChannels_assignsGloballyUniqueIDs() async throws {
        let provider = makeProvider { _ in
            self.json(#"[{"stream_id":1,"name":"Kanal","category_id":"7"}]"#)
        }

        let channels = try await provider.fetchChannels(categoryID: nil)
        // Kimlik kaynağı da içermeli: iki hesapta da "1" numaralı kanal olabilir.
        XCTAssertEqual(channels[0].id.value, "p1#live#1")
        XCTAssertEqual(channels[0].categoryID?.value, "p1#live#7")
    }

    // MARK: - Kategoriler

    func test_fetchCategories_preservesPanelOrder() async throws {
        let provider = makeProvider { _ in
            self.json("""
                [{"category_id":"1","category_name":"ULUSAL"},
                 {"category_id":"2","category_name":"SPOR"}]
                """)
        }

        let categories = try await provider.fetchCategories(kind: .live)
        XCTAssertEqual(categories.map(\.name), ["ULUSAL", "SPOR"])
        XCTAssertEqual(categories.map(\.sortOrder), [0, 1])
        XCTAssertEqual(categories[0].kind, .live)
    }

    func test_categoryFilter_sendsPanelRawID() async throws {
        // Ekranlar global kimlik taşır; panel kendi ham kimliğini bekler.
        let capturedURL = LockedBox<URL?>(nil)
        let provider = makeProvider { url in
            capturedURL.set(url)
            return self.json("[]")
        }

        _ = try await provider.fetchChannels(categoryID: MediaCategory.ID("p1#live#42"))

        let query = capturedURL.get()?.query ?? ""
        XCTAssertTrue(query.contains("category_id=42"), "Ham kategori kimliği gönderilmeli: \(query)")
        XCTAssertFalse(query.contains("p1%23live"), "Global kimlik panele gönderilmemeli")
    }

    // MARK: - Filmler ve diziler

    func test_fetchMovies_defaultsContainerExtension() async throws {
        let provider = makeProvider { _ in
            self.json("""
                [{"stream_id":9,"name":"Film","rating":"7.5","added":"1600000000"},
                 {"stream_id":10,"name":"Film 2","container_extension":"mkv"}]
                """)
        }

        let movies = try await provider.fetchMovies(categoryID: nil)
        // Uzantı olmadan akış adresi kurulamaz; panellerin varsayılanı mp4.
        XCTAssertEqual(movies[0].containerExtension, "mp4")
        XCTAssertEqual(movies[0].rating, 7.5)
        XCTAssertEqual(movies[0].addedAt, Date(timeIntervalSince1970: 1_600_000_000))
        XCTAssertEqual(movies[1].containerExtension, "mkv")
    }

    func test_fetchSeries_splitsCommaSeparatedLists() async throws {
        let provider = makeProvider { _ in
            self.json("""
                [{"series_id":77,"name":"Dizi","genre":"Dram, Gerilim",
                  "cast":"Ali Veli, Ayşe Fatma","releaseDate":"2020-05-17",
                  "rating":"8.4","backdrop_path":["http://img.example.com/b.jpg"]}]
                """)
        }

        let series = try await provider.fetchSeries(categoryID: nil)
        XCTAssertEqual(series[0].genres, ["Dram", "Gerilim"])
        XCTAssertEqual(series[0].cast, ["Ali Veli", "Ayşe Fatma"])
        XCTAssertEqual(series[0].rating, 8.4)
        XCTAssertNotNil(series[0].releaseDate)
        XCTAssertEqual(series[0].backdropURL?.absoluteString, "http://img.example.com/b.jpg")
        XCTAssertEqual(series[0].streamKey, "77", "Sezon ağacını çekmek için ham kimlik gerekli")
    }

    // MARK: - Akış adresleri

    func test_streamURL_forLiveUsesRequestedFormat() {
        let channel = Channel(
            id: "p1#live#1", playlistID: "p1", name: "TRT 1", streamKey: "12345"
        )

        let hlsProvider = makeProvider(liveFormat: .hls) { _ in Data() }
        XCTAssertEqual(
            hlsProvider.streamURL(for: channel)?.absoluteString,
            "http://panel.example.com:8080/live/kullanici/parola/12345.m3u8"
        )

        let tsProvider = makeProvider(liveFormat: .mpegTS) { _ in Data() }
        XCTAssertEqual(
            tsProvider.streamURL(for: channel)?.absoluteString,
            "http://panel.example.com:8080/live/kullanici/parola/12345.ts"
        )
    }

    func test_streamURL_forMovieAndEpisode() {
        let provider = makeProvider { _ in Data() }

        let movie = Movie(
            id: "p1#vod#9", playlistID: "p1", title: "Film",
            streamKey: "9", containerExtension: "mkv"
        )
        XCTAssertEqual(
            provider.streamURL(for: movie)?.absoluteString,
            "http://panel.example.com:8080/movie/kullanici/parola/9.mkv"
        )

        let episode = Episode(
            id: "p1#series#77#e#101", seriesID: "p1#series#77", seasonNumber: 1,
            number: 1, title: "Bölüm 1", streamKey: "101", containerExtension: "mp4"
        )
        XCTAssertEqual(
            provider.streamURL(for: episode)?.absoluteString,
            "http://panel.example.com:8080/series/kullanici/parola/101.mp4"
        )
    }

    func test_streamHeaders_includeUserAgent() {
        // Paneller User-Agent denetler; motorlar bu başlığı iletmek zorunda.
        let provider = makeProvider { _ in Data() }
        XCTAssertNotNil(provider.streamHeaders["User-Agent"])
    }
}

// MARK: - Test yardımcıları

struct StubHTTPClient: HTTPClient {
    let handler: @Sendable (URL) throws -> Data

    func get(_ url: URL, headers: [String: String]) async throws -> Data {
        try handler(url)
    }
}

/// Sendable closure içinden değer yakalamak için küçük kilit.
final class LockedBox<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) { self.value = value }

    func set(_ newValue: Value) {
        lock.lock(); defer { lock.unlock() }
        value = newValue
    }

    func get() -> Value {
        lock.lock(); defer { lock.unlock() }
        return value
    }
}
