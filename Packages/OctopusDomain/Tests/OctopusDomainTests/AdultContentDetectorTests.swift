import XCTest
@testable import OctopusDomain

/// Yetişkin içerik tespiti — sahadaki kategori adlarıyla.
///
/// Buradaki örneklerin çoğu gerçek panellerden: sağlayıcılar `is_adult`
/// alanını doldurmuyor, işaretleme kategori adında oluyor.
final class AdultContentDetectorTests: XCTestCase {

    // MARK: - Yakalanması gerekenler

    func test_recognizesCommonAdultCategories() {
        let names = [
            "XXX",
            "xxx",
            "ADULT",
            "Adult",
            "18+",
            "+18",
            "EROTIK",
            "Erotik",
            "EROTİK",          // Türkçe noktalı İ
            "PORNO",
            "TR | XXX",        // ayraçlı
            "VOD-ADULT",
            "18+ FILM",
            "PL|XXX",
            "TR-XXX24",        // bitişik yazım
            "  xxx  ",         // boşluklu
            "Hardcore"
        ]

        for name in names {
            XCTAssertTrue(
                AdultContentDetector.isAdult(categoryName: name),
                "Yakalanmalıydı: '\(name)'"
            )
        }
    }

    // MARK: - Yakalanmaması gerekenler

    func test_doesNotFlagOrdinaryCategories() {
        let names = [
            "Spor",
            "Haber",
            "Belgesel",
            "Çocuk",
            "TR | ULUSAL",
            "Aksiyon",
            "Filmler",
            "Essex",            // "sex" içeriyor ama ayrı sözcük değil
            "Sussex TV",
            "Middlesex",
            "Adulthood",        // "adult" ile başlıyor ama ayrı sözcük değil
            "",
            "   "
        ]

        for name in names {
            XCTAssertFalse(
                AdultContentDetector.isAdult(categoryName: name),
                "Yanlışlıkla işaretlendi: '\(name)'"
            )
        }
    }

    func test_nilCategoryIsNotAdult() {
        XCTAssertFalse(AdultContentDetector.isAdult(categoryName: nil))
    }

    // MARK: - Sağlayıcı bayrağı

    func test_providerFlagWins() {
        // Panel "yetişkin" diyorsa kategori adına bakılmaz.
        XCTAssertTrue(
            AdultContentDetector.isAdult(providerFlag: true, categoryName: "Spor")
        )
    }

    func test_falseProviderFlagDoesNotOverrideCategory() {
        // ⚠️ Panel `false` dese bile kategori adı "XXX" ise gizlenir.
        // Hata yönü kasıtlı: eksik gizlemek kilidi anlamsız kılar.
        XCTAssertTrue(
            AdultContentDetector.isAdult(providerFlag: false, categoryName: "XXX")
        )
    }

    // MARK: - Katalog damgalama

    private func makeCategory(_ id: String, _ name: String) -> MediaCategory {
        MediaCategory(id: MediaCategory.ID(id), playlistID: "p1", kind: .live, name: name)
    }

    private func makeChannel(_ id: String, categoryID: String?) -> Channel {
        Channel(
            id: Channel.ID(id),
            playlistID: "p1",
            name: "Kanal \(id)",
            streamKey: id,
            categoryID: categoryID.map { MediaCategory.ID($0) }
        )
    }

    func test_markingUsesCategoryMembership() {
        let categories = [makeCategory("c1", "Spor"), makeCategory("c2", "XXX")]
        let channels = [
            makeChannel("1", categoryID: "c1"),
            makeChannel("2", categoryID: "c2"),
            makeChannel("3", categoryID: nil)
        ]

        let marked = AdultContentDetector.markAdultContent(channels, categories: categories)

        XCTAssertFalse(marked[0].isAdult)
        XCTAssertTrue(marked[1].isAdult, "XXX kategorisindeki kanal işaretlenmeli")
        XCTAssertFalse(marked[2].isAdult, "Kategorisi olmayan kanal işaretlenmemeli")
    }

    func test_markingPreservesOrderAndCount() {
        let categories = [makeCategory("c2", "ADULT")]
        let channels = (0..<5).map { makeChannel("\($0)", categoryID: "c2") }

        let marked = AdultContentDetector.markAdultContent(channels, categories: categories)

        XCTAssertEqual(marked.map(\.id), channels.map(\.id))
        XCTAssertTrue(marked.allSatisfy(\.isAdult))
    }

    func test_markingKeepsExistingFlag() {
        // Sağlayıcı zaten işaretlediyse kategori temiz olsa da korunur.
        var channel = makeChannel("1", categoryID: "c1")
        channel.isAdult = true

        let marked = AdultContentDetector.markAdultContent(
            [channel],
            categories: [makeCategory("c1", "Spor")]
        )

        XCTAssertTrue(marked[0].isAdult)
    }

    func test_noAdultCategoriesLeavesCatalogUntouched() {
        let categories = [makeCategory("c1", "Spor"), makeCategory("c2", "Haber")]
        let channels = [makeChannel("1", categoryID: "c1"), makeChannel("2", categoryID: "c2")]

        let marked = AdultContentDetector.markAdultContent(channels, categories: categories)

        XCTAssertTrue(marked.allSatisfy { !$0.isAdult })
    }

    func test_marksMoviesAndSeriesToo() {
        let categories = [makeCategory("c1", "XXX")]

        let movies = [
            Movie(
                id: "m1",
                playlistID: "p1",
                title: "Film",
                streamKey: "1",
                categoryID: MediaCategory.ID("c1")
            )
        ]
        let series = [
            Series(
                id: "s1",
                playlistID: "p1",
                title: "Dizi",
                streamKey: "1",
                categoryID: MediaCategory.ID("c1")
            )
        ]

        XCTAssertTrue(
            AdultContentDetector.markAdultContent(movies, categories: categories)[0].isAdult
        )
        XCTAssertTrue(
            AdultContentDetector.markAdultContent(series, categories: categories)[0].isAdult
        )
    }
}
