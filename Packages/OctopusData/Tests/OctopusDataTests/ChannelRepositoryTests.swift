import XCTest
import GRDB
import OctopusDomain
@testable import OctopusData

/// Kanal deposu: filtreleme, arama ve canlı gözlem.
final class ChannelRepositoryTests: XCTestCase {

    private var database: AppDatabase!
    private var repository: GRDBChannelRepository!

    override func setUp() async throws {
        database = try AppDatabase.makeInMemory()
        repository = GRDBChannelRepository(database: database)
        try await seedPlaylist()
    }

    // MARK: - Listeleme

    func test_channels_filtersByPlaylistAndCategory() async throws {
        try await insertChannel(id: "c1", category: "spor", name: "Spor 1", sortOrder: 1)
        try await insertChannel(id: "c2", category: "spor", name: "Spor 2", sortOrder: 2)
        try await insertChannel(id: "c3", category: "haber", name: "Haber 1", sortOrder: 3)

        let all = try await repository.channels(playlistID: "p1", categoryID: nil)
        XCTAssertEqual(all.count, 3)

        let sports = try await repository.channels(playlistID: "p1", categoryID: "spor")
        XCTAssertEqual(sports.map(\.name), ["Spor 1", "Spor 2"])
    }

    func test_channels_orderIsStable() async throws {
        // Sıralama sabit olmalı: sayfalı yükleme sırasında liste kaymamalı.
        // (Referans projede "filmler sürekli değişiyor" şikâyetinin sebebi.)
        try await insertChannel(id: "c3", category: nil, name: "C", sortOrder: 5)
        try await insertChannel(id: "c1", category: nil, name: "A", sortOrder: 1)
        try await insertChannel(id: "c2", category: nil, name: "B", sortOrder: 3)

        let first = try await repository.channels(playlistID: "p1", categoryID: nil)
        let second = try await repository.channels(playlistID: "p1", categoryID: nil)

        XCTAssertEqual(first.map(\.name), ["A", "B", "C"])
        XCTAssertEqual(first.map(\.id), second.map(\.id), "Aynı sorgu farklı sıra döndürdü")
    }

    func test_channelsFromOtherPlaylist_areNotVisible() async throws {
        try await insertPlaylist(id: "p2")
        try await insertChannel(id: "c1", category: nil, name: "Bizim", sortOrder: 1)
        try await insertChannel(id: "c2", category: nil, name: "Diğer", sortOrder: 1, playlist: "p2")

        let ours = try await repository.channels(playlistID: "p1", categoryID: nil)
        XCTAssertEqual(ours.map(\.name), ["Bizim"])
    }

    // MARK: - Arama

    func test_search_matchesPrefix() async throws {
        try await insertChannel(id: "c1", category: nil, name: "Spor Kanalı", sortOrder: 1)
        try await insertChannel(id: "c2", category: nil, name: "Haber Kanalı", sortOrder: 2)

        // Kullanıcı yazarken önek eşleşmesi çalışmalı: "spo" → "Spor Kanalı"
        let results = try await repository.search(query: "spo", playlistID: "p1", limit: 10)
        XCTAssertEqual(results.map(\.name), ["Spor Kanalı"])
    }

    func test_search_withSpecialCharacters_doesNotCrash() async throws {
        try await insertChannel(id: "c1", category: nil, name: "Spor Kanalı", sortOrder: 1)

        // Ham metin doğrudan MATCH'e verilseydi bunlar sözdizimi hatası üretirdi.
        for query in ["\"", "*", "AND", "((", "a\"b"] {
            _ = try await repository.search(query: query, playlistID: "p1", limit: 10)
        }
    }

    func test_search_emptyQuery_returnsEmpty() async throws {
        try await insertChannel(id: "c1", category: nil, name: "Spor", sortOrder: 1)
        let results = try await repository.search(query: "   ", playlistID: "p1", limit: 10)
        XCTAssertTrue(results.isEmpty)
    }

    func test_search_respectsPlaylistBoundary() async throws {
        try await insertPlaylist(id: "p2")
        try await insertChannel(id: "c2", category: nil, name: "Spor Diğer", sortOrder: 1, playlist: "p2")

        let results = try await repository.search(query: "spor", playlistID: "p1", limit: 10)
        XCTAssertTrue(results.isEmpty, "Arama başka kaynağın kanalını döndürdü")
    }

    // MARK: - Canlı gözlem
    //
    // Offline-first akışın kalbi: senkronizasyon yazdıkça ekran tazelenir.

    func test_observeChannels_emitsCurrentStateImmediately() async throws {
        try await insertChannel(id: "c1", category: nil, name: "İlk", sortOrder: 1)

        let stream = repository.observeChannels(playlistID: "p1", categoryID: nil)
        var iterator = stream.makeAsyncIterator()

        let firstEmission = await iterator.next()
        XCTAssertEqual(firstEmission?.map(\.name), ["İlk"], "Gözlem mevcut durumu hemen vermeli")
    }

    func test_observeChannels_emitsAgainAfterInsert() async throws {
        let stream = repository.observeChannels(playlistID: "p1", categoryID: nil)
        var iterator = stream.makeAsyncIterator()

        // İlk yayın: boş liste
        let initial = await iterator.next()
        XCTAssertEqual(initial?.count, 0)

        // Senkronizasyonun yazması simüle edilir
        try await insertChannel(id: "c1", category: nil, name: "Yeni", sortOrder: 1)

        let afterInsert = await iterator.next()
        XCTAssertEqual(afterInsert?.map(\.name), ["Yeni"], "Yazma sonrası gözlem tetiklenmedi")
    }

    // MARK: - Kategoriler

    func test_categories_onlyReturnsLiveKind() async throws {
        try await insertCategory(id: "spor", kind: "live", name: "Spor")
        try await insertCategory(id: "aksiyon", kind: "movie", name: "Aksiyon")

        let categories = try await repository.categories(playlistID: "p1")
        XCTAssertEqual(categories.map(\.name), ["Spor"], "Film kategorisi canlı listesine sızdı")
    }

    // MARK: - Test verisi

    private func seedPlaylist() async throws {
        try await insertPlaylist(id: "p1")
    }

    private func insertPlaylist(id: String) async throws {
        try await database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO playlist (id, name, kindType, createdAt, isActive)
                    VALUES (?, ?, 'm3u', '2026-01-01 00:00:00', 0)
                    """,
                arguments: [id, "Kaynak \(id)"]
            )
        }
    }

    private func insertCategory(id: String, kind: String, name: String) async throws {
        try await database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO category (id, playlistId, kind, name, sortOrder)
                    VALUES (?, 'p1', ?, ?, 0)
                    """,
                arguments: [id, kind, name]
            )
        }
    }

    private func insertChannel(
        id: String,
        category: String?,
        name: String,
        sortOrder: Int,
        playlist: String = "p1",
        number: Int? = nil
    ) async throws {
        try await database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO channel
                        (id, playlistId, name, streamKey, categoryId, sortOrder, number, isAdult)
                    VALUES (?, ?, ?, ?, ?, ?, ?, 0)
                    """,
                arguments: [id, playlist, name, "raw-\(id)", category, sortOrder, number]
            )
        }
    }
}

/// Numarayla kanal bulma — "205'e geç" akışı.
final class ChannelNumberLookupTests: XCTestCase {

    private var database: AppDatabase!
    private var repository: GRDBChannelRepository!

    override func setUp() async throws {
        database = try AppDatabase.makeInMemory()
        repository = GRDBChannelRepository(database: database)

        try await database.write { db in
            for id in ["p1", "p2"] {
                try db.execute(
                    sql: """
                        INSERT INTO playlist (id, name, kindType, createdAt, isActive)
                        VALUES (?, ?, 'm3u', '2026-01-01 00:00:00', 0)
                        """,
                    arguments: [id, "Kaynak \(id)"]
                )
            }
        }
    }

    func test_findsChannelByNumber() async throws {
        try await insert(id: "c1", name: "Bir", number: 1, sortOrder: 0)
        try await insert(id: "c205", name: "İki Yüz Beş", number: 205, sortOrder: 1)

        let found = try await repository.channel(number: 205, playlistID: "p1")
        XCTAssertEqual(found?.name, "İki Yüz Beş")
    }

    func test_missingNumberReturnsNil() async throws {
        try await insert(id: "c1", name: "Bir", number: 1, sortOrder: 0)
        let found = try await repository.channel(number: 999, playlistID: "p1")
        XCTAssertNil(found)
    }

    func test_numberIsScopedToPlaylist() async throws {
        // Kaynaklar aynı numarayı kullanır; başka kaynağın kanalı gelmemeli.
        try await insert(id: "a", name: "Kaynak 1", number: 5, sortOrder: 0, playlist: "p1")
        try await insert(id: "b", name: "Kaynak 2", number: 5, sortOrder: 0, playlist: "p2")

        let found = try await repository.channel(number: 5, playlistID: "p2")
        XCTAssertEqual(found?.name, "Kaynak 2")
    }

    func test_duplicateNumberReturnsFirstInListOrder() async throws {
        // ⚠️ Numara benzersiz değil: sağlayıcılar SD/HD için tekrar ediyor.
        // Liste sırasındaki ilki dönmeli — kullanıcının beklediği o.
        try await insert(id: "hd", name: "Kanal HD", number: 5, sortOrder: 9)
        try await insert(id: "sd", name: "Kanal SD", number: 5, sortOrder: 2)

        let found = try await repository.channel(number: 5, playlistID: "p1")
        XCTAssertEqual(found?.name, "Kanal SD")
    }

    private func insert(
        id: String,
        name: String,
        number: Int,
        sortOrder: Int,
        playlist: String = "p1"
    ) async throws {
        try await database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO channel
                        (id, playlistId, name, streamKey, sortOrder, number, isAdult)
                    VALUES (?, ?, ?, ?, ?, ?, 0)
                    """,
                arguments: [id, playlist, name, "raw-\(id)", sortOrder, number]
            )
        }
    }
}
