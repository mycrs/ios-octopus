import XCTest
import GRDB
import OctopusDomain
@testable import OctopusData

/// Katalog sayfalaması — sıralamanın **kesin** olması.
///
/// ⚠️ IPTV listelerinde aynı film birden çok kez, birebir aynı adla
/// geçiyor (sağlayıcı farklı kaliteleri ayrı akış olarak veriyor).
/// Yalnızca `title` ile sıralarken eşit başlıkların sırası SQLite'ın
/// keyfine kalıyordu: aynı film iki sayfada birden çıkabilir, başka biri
/// hiç görünmeyebilirdi. Referans projedeki "filmler sürekli değişiyor"
/// şikâyetinin sebeplerinden biri buydu.
final class CatalogPaginationTests: XCTestCase {

    private var database: AppDatabase!
    private var vod: GRDBVODRepository!
    private var series: GRDBSeriesRepository!

    override func setUp() async throws {
        database = try AppDatabase.makeInMemory()
        vod = GRDBVODRepository(database: database)
        series = GRDBSeriesRepository(database: database)

        try await database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO playlist (id, name, kindType, createdAt, isActive)
                    VALUES ('p1', 'Kaynak', 'm3u', '2026-01-01 00:00:00', 1)
                    """
            )
        }
    }

    // MARK: - Film

    func test_moviePagesDoNotOverlapWithDuplicateTitles() async throws {
        // Hepsi aynı ada sahip: beraberlik bozucu yoksa sıra belirsiz.
        for index in 0..<20 {
            try await insertMovie(id: "m\(index)", title: "Aynı Film")
        }

        var seen: [String] = []
        for page in 0..<4 {
            let items = try await vod.movies(
                playlistID: "p1",
                categoryID: nil,
                limit: 5,
                offset: page * 5
            )
            seen.append(contentsOf: items.map(\.id.value))
        }

        XCTAssertEqual(seen.count, 20)
        XCTAssertEqual(Set(seen).count, 20, "Aynı film iki sayfada birden çıkmamalı")
    }

    func test_movieOrderIsRepeatable() async throws {
        for index in 0..<10 {
            try await insertMovie(id: "m\(index)", title: "Film")
        }

        let first = try await vod.movies(playlistID: "p1", categoryID: nil, limit: 10, offset: 0)
        let second = try await vod.movies(playlistID: "p1", categoryID: nil, limit: 10, offset: 0)

        XCTAssertEqual(first.map(\.id.value), second.map(\.id.value))
    }

    func test_movieTitleOrderStillWins() async throws {
        // Beraberlik bozucu, asıl sıralamayı bozmamalı.
        try await insertMovie(id: "m1", title: "Zebra")
        try await insertMovie(id: "m2", title: "Aslan")

        let items = try await vod.movies(playlistID: "p1", categoryID: nil, limit: 10, offset: 0)
        XCTAssertEqual(items.map(\.title), ["Aslan", "Zebra"])
    }

    // MARK: - Dizi

    func test_seriesPagesDoNotOverlapWithDuplicateTitles() async throws {
        for index in 0..<12 {
            try await insertSeries(id: "s\(index)", title: "Aynı Dizi")
        }

        var seen: [String] = []
        for page in 0..<3 {
            let items = try await series.series(
                playlistID: "p1",
                categoryID: nil,
                limit: 4,
                offset: page * 4
            )
            seen.append(contentsOf: items.map(\.id.value))
        }

        XCTAssertEqual(Set(seen).count, 12, "Aynı dizi iki sayfada birden çıkmamalı")
    }

    // MARK: - Yardımcılar

    private func insertMovie(id: String, title: String) async throws {
        try await database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO movie (id, playlistId, title, streamKey, genres, cast, isAdult)
                    VALUES (?, 'p1', ?, ?, '[]', '[]', 0)
                    """,
                arguments: [id, title, id]
            )
        }
    }

    private func insertSeries(id: String, title: String) async throws {
        try await database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO series (id, playlistId, title, streamKey, genres, cast, isAdult)
                    VALUES (?, 'p1', ?, ?, '[]', '[]', 0)
                    """,
                arguments: [id, title, id]
            )
        }
    }
}
