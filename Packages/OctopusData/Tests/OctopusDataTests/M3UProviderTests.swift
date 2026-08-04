import XCTest
import OctopusDomain
@testable import OctopusData

/// M3U sağlayıcısı: indirme, önbellek ve akış adresi davranışı.
final class M3UProviderTests: XCTestCase {

    private let sourceURL = URL(string: "http://liste.example.com/playlist.m3u")!

    private let samplePlaylist = """
        #EXTM3U
        #EXTINF:-1 tvg-id="trt1.tr" group-title="ULUSAL",TRT 1
        http://sunucu.example.com/1.ts
        #EXTINF:-1 group-title="SPOR",A Spor
        http://sunucu.example.com/2.ts
        """

    private func makeProvider(
        counter: LockedBox<Int>? = nil,
        body: @escaping @Sendable () throws -> Data
    ) -> M3UContentProvider {
        M3UContentProvider(
            sourceURL: sourceURL,
            playlistID: "p1",
            httpClient: StubHTTPClient { _ in
                if let counter { counter.set(counter.get() + 1) }
                return try body()
            }
        )
    }

    // MARK: - Doğrulama

    func test_authenticate_succeedsWhenPlaylistHasChannels() async throws {
        let provider = makeProvider { Data(self.samplePlaylist.utf8) }
        let account = try await provider.authenticate()

        XCTAssertEqual(account.username, "liste.example.com")
        XCTAssertNil(account.expiresAt, "M3U'da abonelik bitiş tarihi yoktur")
    }

    func test_authenticate_failsOnEmptyPlaylist() async throws {
        // Adres doğru ama içerik boşsa kullanıcıya "kaynak eklendi" demek yanıltıcı olur.
        let provider = makeProvider { Data("#EXTM3U\n".utf8) }

        do {
            _ = try await provider.authenticate()
            XCTFail("Boş liste kabul edilmemeliydi")
        } catch let error as AppError {
            guard case .invalidResponse = error else {
                return XCTFail("Beklenen invalidResponse, gelen: \(error)")
            }
        }
    }

    // MARK: - Katalog

    func test_fetchChannels_filtersByCategory() async throws {
        let provider = makeProvider { Data(self.samplePlaylist.utf8) }

        let all = try await provider.fetchChannels(categoryID: nil)
        XCTAssertEqual(all.count, 2)

        let categories = try await provider.fetchCategories(kind: .live)
        let sportsCategory = try XCTUnwrap(categories.first { $0.name == "SPOR" })

        let sports = try await provider.fetchChannels(categoryID: sportsCategory.id)
        XCTAssertEqual(sports.map(\.name), ["A Spor"])
    }

    func test_vodAndSeriesReturnEmptyInsteadOfThrowing() async throws {
        // Klasik M3U'da film/dizi yapısı yok. Hata fırlatmak senkronizasyonu
        // gereksiz yere başarısız gösterirdi.
        let provider = makeProvider { Data(self.samplePlaylist.utf8) }

        let movies = try await provider.fetchMovies(categoryID: nil)
        let series = try await provider.fetchSeries(categoryID: nil)
        let movieCategories = try await provider.fetchCategories(kind: .movie)

        XCTAssertTrue(movies.isEmpty)
        XCTAssertTrue(series.isEmpty)
        XCTAssertTrue(movieCategories.isEmpty)
    }

    // MARK: - Önbellek

    func test_playlistIsDownloadedOnlyOnce() async throws {
        let counter = LockedBox(0)
        let provider = makeProvider(counter: counter) { Data(self.samplePlaylist.utf8) }

        _ = try await provider.fetchCategories(kind: .live)
        _ = try await provider.fetchChannels(categoryID: nil)
        _ = try await provider.fetchChannels(categoryID: nil)

        XCTAssertEqual(counter.get(), 1, "20 MB'lık liste her çağrıda yeniden indirilmemeli")
    }

    func test_concurrentCallsShareSingleDownload() async throws {
        let counter = LockedBox(0)
        let provider = makeProvider(counter: counter) { Data(self.samplePlaylist.utf8) }

        async let first = provider.fetchChannels(categoryID: nil)
        async let second = provider.fetchChannels(categoryID: nil)
        async let third = provider.fetchChannels(categoryID: nil)
        _ = try await (first, second, third)

        XCTAssertEqual(counter.get(), 1, "Eşzamanlı çağrılar aynı indirmeyi beklemeli")
    }

    func test_failedDownloadIsNotCached() async throws {
        let counter = LockedBox(0)
        let provider = makeProvider(counter: counter) {
            if counter.get() == 1 { throw AppError.network(reason: "kopuk") }
            return Data(self.samplePlaylist.utf8)
        }

        _ = try? await provider.fetchChannels(categoryID: nil)
        let channels = try await provider.fetchChannels(categoryID: nil)

        XCTAssertEqual(channels.count, 2, "Başarısız indirme sonraki denemeyi engellememeli")
        XCTAssertEqual(counter.get(), 2)
    }

    func test_invalidateCache_forcesReload() async throws {
        let counter = LockedBox(0)
        let provider = makeProvider(counter: counter) { Data(self.samplePlaylist.utf8) }

        _ = try await provider.fetchChannels(categoryID: nil)
        await provider.invalidateCache()
        _ = try await provider.fetchChannels(categoryID: nil)

        XCTAssertEqual(counter.get(), 2, "Senkronizasyon taze liste isteyebilmeli")
    }

    // MARK: - Kodlama

    func test_latin1PlaylistIsDecoded() async throws {
        // IPTV listeleri her zaman UTF-8 değildir; Latin-1 yaygın ikinci seçenek.
        let text = """
            #EXTM3U
            #EXTINF:-1,Kanal
            http://sunucu.example.com/1.ts
            """
        let latin1 = try XCTUnwrap(text.data(using: .isoLatin1))
        let provider = makeProvider { latin1 }

        let channels = try await provider.fetchChannels(categoryID: nil)
        XCTAssertEqual(channels.count, 1)
    }

    // MARK: - Akış adresleri

    func test_streamURLIsTheAddressFromPlaylist() async throws {
        let provider = makeProvider { Data(self.samplePlaylist.utf8) }
        let channels = try await provider.fetchChannels(categoryID: nil)

        XCTAssertEqual(
            provider.streamURL(for: channels[0])?.absoluteString,
            "http://sunucu.example.com/1.ts"
        )
    }
}
