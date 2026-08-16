import XCTest
import OctopusDomain
@testable import OctopusData

/// İçerikten oynatılabilir akışa geçiş — kaynak türünden bağımsız.
final class StreamResolverTests: XCTestCase {

    private var database: AppDatabase!
    private var playlists: GRDBPlaylistRepository!
    private var progress: GRDBPlaybackProgressRepository!
    private var factory: DefaultContentProviderFactory!
    private var resolver: ProviderStreamResolver!

    override func setUp() async throws {
        database = try AppDatabase.makeInMemory()
        let secrets = FakeSecretStore()
        try secrets.save("parola", for: "playlist.xtream1")

        playlists = GRDBPlaylistRepository(database: database, secrets: secrets)
        progress = GRDBPlaybackProgressRepository(database: database)
        factory = DefaultContentProviderFactory(
            httpClient: StubHTTPClient { _ in Data("#EXTM3U\n".utf8) },
            secrets: secrets
        )
        resolver = ProviderStreamResolver(
            playlists: playlists,
            providerFactory: factory,
            progress: progress
        )

        try await playlists.add(
            Playlist(
                id: "xtream1",
                name: "Xtream",
                kind: .xtream(
                    host: URL(string: "http://panel.example.com:8080")!,
                    username: "kullanici"
                ),
                createdAt: Date(timeIntervalSince1970: 0)
            ),
            password: nil   // parola zaten Keychain sahtesinde
        )
        try await playlists.add(
            Playlist(
                id: "m3u1",
                name: "M3U",
                kind: .m3u(url: URL(string: "http://liste.example.com/p.m3u")!),
                createdAt: Date(timeIntervalSince1970: 0)
            ),
            password: nil
        )
    }

    // MARK: - Canlı yayın

    func test_xtreamChannel_buildsPanelStyleURL() async throws {
        let channel = Channel(
            id: "xtream1#live#12345",
            playlistID: "xtream1",
            name: "TRT 1",
            streamKey: "12345",
            logoURL: URL(string: "http://logo.example.com/trt1.png")
        )

        let item = try await resolver.playbackItem(for: channel)

        XCTAssertEqual(
            item.url.absoluteString,
            "http://panel.example.com:8080/live/kullanici/parola/12345.m3u8"
        )
        XCTAssertTrue(item.isLive)
        XCTAssertNil(item.resumeAt, "Canlı yayın kaldığı yerden devam edemez")
        XCTAssertEqual(item.title, "TRT 1")
        XCTAssertEqual(item.artworkURL?.absoluteString, "http://logo.example.com/trt1.png")
        XCTAssertNotNil(item.headers["User-Agent"], "Paneller User-Agent denetler")
        XCTAssertEqual(item.format, .hls)
    }

    func test_m3uChannel_usesAddressFromPlaylist() async throws {
        // Aynı çağrı, tamamen farklı adres kurulumu — çağıran farkı görmez.
        let channel = Channel(
            id: "m3u1#live#x",
            playlistID: "m3u1",
            name: "Kanal",
            streamKey: "http://sunucu.example.com/yayin.ts"
        )

        let item = try await resolver.playbackItem(for: channel)

        XCTAssertEqual(item.url.absoluteString, "http://sunucu.example.com/yayin.ts")
        XCTAssertEqual(item.format, .mpegTS, "Format adresten çıkarılmalı")
    }

    // MARK: - Kaldığı yerden devam

    func test_movie_resumesFromStoredPosition() async throws {
        let movie = Movie(
            id: "xtream1#vod#9",
            playlistID: "xtream1",
            title: "Film",
            streamKey: "9",
            containerExtension: "mkv"
        )

        try await progress.save(
            PlaybackProgress(
                itemKey: "",
                positionSeconds: 620,
                durationSeconds: 5_400,
                updatedAt: Date(timeIntervalSince1970: 100)
            ),
            for: .movie(movie.id)
        )

        let item = try await resolver.playbackItem(for: movie)

        XCTAssertEqual(item.resumeAt, 620)
        XCTAssertFalse(item.isLive)
        XCTAssertEqual(
            item.url.absoluteString,
            "http://panel.example.com:8080/movie/kullanici/parola/9.mkv"
        )
    }

    func test_finishedMovie_startsFromBeginning() async throws {
        let movie = Movie(
            id: "xtream1#vod#9", playlistID: "xtream1",
            title: "Film", streamKey: "9"
        )

        // %99 izlenmiş — bitmiş sayılır, baştan başlamalı.
        try await progress.save(
            PlaybackProgress(
                itemKey: "",
                positionSeconds: 5_346,
                durationSeconds: 5_400,
                updatedAt: Date(timeIntervalSince1970: 100)
            ),
            for: .movie(movie.id)
        )

        let item = try await resolver.playbackItem(for: movie)
        XCTAssertNil(item.resumeAt, "İzlenmiş film baştan açılmalı")
    }

    func test_movieWithoutProgress_hasNoResumePoint() async throws {
        let movie = Movie(
            id: "xtream1#vod#9", playlistID: "xtream1",
            title: "Film", streamKey: "9"
        )
        let item = try await resolver.playbackItem(for: movie)
        XCTAssertNil(item.resumeAt)
    }

    // MARK: - Dizi bölümü

    func test_episode_carriesSeriesContextInSubtitle() async throws {
        let series = Series(
            id: "xtream1#series#77",
            playlistID: "xtream1",
            title: "Dizi Adı",
            streamKey: "77",
            posterURL: URL(string: "http://img.example.com/poster.jpg")
        )
        let episode = Episode(
            id: "xtream1#series#77#e#101",
            seriesID: series.id,
            seasonNumber: 2,
            number: 7,
            title: "Bölüm Adı",
            streamKey: "101",
            containerExtension: "mp4"
        )

        let item = try await resolver.playbackItem(for: episode, in: series)

        XCTAssertEqual(item.title, "Bölüm Adı")
        XCTAssertEqual(item.subtitle, "Dizi Adı · S02B07")
        XCTAssertEqual(
            item.url.absoluteString,
            "http://panel.example.com:8080/series/kullanici/parola/101.mp4"
        )
        XCTAssertEqual(item.artworkURL?.absoluteString, "http://img.example.com/poster.jpg")
    }

    // MARK: - Hata durumları

    func test_deletedPlaylist_throwsNotFound() async throws {
        // Kaynak silinmiş ama ekran hâlâ açık olabilir.
        let channel = Channel(
            id: "yok#live#1", playlistID: "yok", name: "Kanal", streamKey: "1"
        )

        do {
            _ = try await resolver.playbackItem(for: channel)
            XCTFail("Silinmiş kaynak için hata verilmeliydi")
        } catch {
            XCTAssertEqual(error as? AppError, .notFound)
        }
    }

    // MARK: - Sağlayıcı önbelleği

    func test_providerIsReusedAcrossCalls() async throws {
        // M3U sağlayıcısı indirdiği listeyi kendi içinde tutar; her çağrıda
        // yenisi kurulursa 20 MB'lık liste tekrar tekrar iner.
        let fetched = try await playlists.playlist(id: "m3u1")
        let playlist = try XCTUnwrap(fetched)

        let first = try await factory.makeProvider(for: playlist)
        let second = try await factory.makeProvider(for: playlist)

        XCTAssertTrue(
            (first as AnyObject) === (second as AnyObject),
            "Aynı kaynak için aynı sağlayıcı örneği dönmeli"
        )
    }

    func test_editingSourceAddressForcesNewProvider() async throws {
        // ⚠️ Önbellek yalnızca `id` ile anahtarlanıyordu: kullanıcı sunucu
        // adresini değiştirse bile eski adrese bakan sağlayıcı oturum boyunca
        // kullanılmaya devam ediyordu. `invalidate` üretimde hiçbir yerden
        // çağrılmadığı için kimse fark etmiyordu.
        let fetched = try await playlists.playlist(id: "m3u1")
        let original = try XCTUnwrap(fetched)

        let before = try await factory.makeProvider(for: original)

        let newURL = try XCTUnwrap(URL(string: "http://yeni.example.com/liste.m3u"))
        var edited = original
        edited.kind = .m3u(url: newURL)
        try await playlists.update(edited)

        let after = try await factory.makeProvider(for: edited)

        XCTAssertFalse(
            (before as AnyObject) === (after as AnyObject),
            "Adres değişince yeni sağlayıcı kurulmalı"
        )
    }

    func test_invalidate_forcesNewProvider() async throws {
        let fetched = try await playlists.playlist(id: "m3u1")
        let playlist = try XCTUnwrap(fetched)

        let first = try await factory.makeProvider(for: playlist)
        await factory.invalidate(playlistID: "m3u1")
        let second = try await factory.makeProvider(for: playlist)

        XCTAssertFalse((first as AnyObject) === (second as AnyObject))
    }

    func test_activationCodeSource_reportsUnsupportedForNow() async throws {
        try await playlists.add(
            Playlist(
                id: "act1",
                name: "Kod",
                kind: .activationCode(code: "ABC-123"),
                createdAt: Date(timeIntervalSince1970: 0)
            ),
            password: nil
        )
        let fetched = try await playlists.playlist(id: "act1")
        let playlist = try XCTUnwrap(fetched)

        do {
            _ = try await factory.makeProvider(for: playlist)
            XCTFail("Aktivasyon kodu henüz desteklenmiyor")
        } catch {
            XCTAssertNotNil(error as? AppError)
        }
    }
}
