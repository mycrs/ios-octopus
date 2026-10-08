import XCTest
import GRDB
import OctopusDomain
@testable import OctopusData

final class CatalogDetailRequestTests: XCTestCase {
    private var database: AppDatabase!

    override func setUp() async throws {
        database = try AppDatabase.makeInMemory()
        try await database.write { db in
            try db.execute(sql: """
                INSERT INTO playlist (id, name, kindType, createdAt, isActive)
                VALUES ('p1', 'Kaynak', 'm3u', '2026-01-01 00:00:00', 1)
                """)
            try MovieRecord(Movie(
                id: "m1", playlistID: "p1", title: "Katalog adı", streamKey: "77",
                containerExtension: "mkv", posterURL: URL(string: "https://x/poster.jpg"),
                categoryID: "cat", rating: 8, genres: ["Drama"],
                isAdult: true, addedAt: Date(timeIntervalSince1970: 100), sortOrder: 42
            )).insert(db)
            try SeriesRecord(Series(
                id: "s1", playlistID: "p1", title: "Dizi", streamKey: "88"
            )).insert(db)
        }
    }

    func test_concurrentMovieDetails_shareOneRequestAndCache() async throws {
        let started = expectation(description: "İlk film isteği")
        let duplicate = expectation(description: "Aynı film için ek istek")
        duplicate.isInverted = true
        let gate = DetailRequestGate(started: started, duplicate: duplicate)
        let repository = GRDBVODRepository(database: database, detailLoader: GatedMovieLoader(gate: gate))
        let requests = (0..<8).map { _ in Task { try await repository.loadDetails(id: "m1") } }

        await fulfillment(of: [started], timeout: 2)
        await fulfillment(of: [duplicate], timeout: 0.15)
        await gate.open()
        for request in requests {
            let movie = try await request.value
            XCTAssertEqual(movie.plot, "Uzak özet")
        }
        _ = try await repository.loadDetails(id: "m1")
        let count = await gate.callCount
        XCTAssertEqual(count, 1)
    }

    func test_concurrentSeriesDetails_shareOneRequestAndTreeWrite() async throws {
        let started = expectation(description: "İlk dizi isteği")
        let duplicate = expectation(description: "Aynı dizi için ek istek")
        duplicate.isInverted = true
        let gate = DetailRequestGate(started: started, duplicate: duplicate)
        let repository = GRDBSeriesRepository(database: database, detailLoader: GatedSeriesLoader(gate: gate))
        let requests = (0..<8).map { _ in Task { try await repository.loadDetails(id: "s1") } }

        await fulfillment(of: [started], timeout: 2)
        await fulfillment(of: [duplicate], timeout: 0.15)
        await gate.open()
        for request in requests { try await request.value }
        try await repository.loadDetails(id: "s1")
        let episodes = try await repository.episodes(seriesID: "s1", seasonNumber: 1)
        let count = await gate.callCount
        XCTAssertEqual(count, 1)
        XCTAssertEqual(episodes.count, 1)
    }

    func test_movieDetails_preserveCatalogIdentityOrderAndProtection() async throws {
        let gate = DetailRequestGate(isOpen: true)
        let repository = GRDBVODRepository(database: database, detailLoader: GatedMovieLoader(gate: gate))

        let movie = try await repository.loadDetails(id: "m1")
        let fetched = try await repository.movie(id: "m1")
        let stored = try XCTUnwrap(fetched)

        XCTAssertEqual(movie, stored)
        XCTAssertEqual(stored.title, "Katalog adı")
        XCTAssertEqual(stored.streamKey, "77")
        XCTAssertEqual(stored.sortOrder, 42)
        XCTAssertEqual(stored.categoryID, "cat")
        XCTAssertEqual(stored.containerExtension, "mkv")
        XCTAssertEqual(stored.posterURL?.absoluteString, "https://x/poster.jpg")
        XCTAssertEqual(stored.addedAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(stored.genres, ["Drama"])
        XCTAssertEqual(stored.rating, 8)
        XCTAssertTrue(stored.isAdult)
        XCTAssertEqual(stored.plot, "Uzak özet")
    }

    func test_movieDetails_preserveCatalogChangesMadeDuringRequest() async throws {
        let started = expectation(description: "Film isteği")
        let gate = DetailRequestGate(started: started)
        let repository = GRDBVODRepository(database: database, detailLoader: GatedMovieLoader(gate: gate))
        let request = Task { try await repository.loadDetails(id: "m1") }
        await fulfillment(of: [started], timeout: 2)

        try await database.write { db in
            try db.execute(sql: "UPDATE movie SET sortOrder = 99, categoryId = 'new' WHERE id = 'm1'")
        }
        await gate.open()
        let movie = try await request.value

        XCTAssertEqual(movie.sortOrder, 99)
        XCTAssertEqual(movie.categoryID, "new")
    }

    func test_failedMovieDetails_canRetry() async throws {
        let gate = DetailRequestGate(isOpen: true, shouldFail: true)
        let repository = GRDBVODRepository(database: database, detailLoader: GatedMovieLoader(gate: gate))
        let fallback = try await repository.loadDetails(id: "m1")
        XCTAssertNil(fallback.plot)

        await gate.setFailure(false)
        let retried = try await repository.loadDetails(id: "m1")
        let count = await gate.callCount
        XCTAssertEqual(retried.plot, "Uzak özet")
        XCTAssertEqual(count, 2)
    }

    func test_failedSeriesDetails_canRetry() async throws {
        let gate = DetailRequestGate(isOpen: true, shouldFail: true)
        let repository = GRDBSeriesRepository(database: database, detailLoader: GatedSeriesLoader(gate: gate))
        do {
            try await repository.loadDetails(id: "s1")
            XCTFail("İlk istek başarısız olmalı")
        } catch { XCTAssertTrue(error is AppError) }

        await gate.setFailure(false)
        try await repository.loadDetails(id: "s1")
        let count = await gate.callCount
        XCTAssertEqual(count, 2)
    }

    func test_cancelledMovieCaller_doesNotCancelSharedRequestOrReceiveResult() async throws {
        let started = expectation(description: "Film isteği")
        let gate = DetailRequestGate(started: started)
        let repository = GRDBVODRepository(database: database, detailLoader: GatedMovieLoader(gate: gate))
        let cancelled = Task { try await repository.loadDetails(id: "m1") }
        await fulfillment(of: [started], timeout: 2)
        let remaining = Task { try await repository.loadDetails(id: "m1") }
        cancelled.cancel()
        await gate.open()

        do {
            _ = try await cancelled.value
            XCTFail("İptal edilen çağrı sonuç almamalı")
        } catch { XCTAssertTrue(error is CancellationError) }
        let movie = try await remaining.value
        let count = await gate.callCount
        XCTAssertEqual(movie.plot, "Uzak özet")
        XCTAssertEqual(count, 1)
    }
}

private actor DetailRequestGate {
    private let started: XCTestExpectation?
    private let duplicate: XCTestExpectation?
    private var isOpen: Bool
    private var shouldFail: Bool
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private(set) var callCount = 0

    init(
        started: XCTestExpectation? = nil,
        duplicate: XCTestExpectation? = nil,
        isOpen: Bool = false,
        shouldFail: Bool = false
    ) {
        self.started = started
        self.duplicate = duplicate
        self.isOpen = isOpen
        self.shouldFail = shouldFail
    }

    func wait() async throws {
        callCount += 1
        if callCount == 1 { started?.fulfill() } else { duplicate?.fulfill() }
        if !isOpen {
            await withCheckedContinuation { continuations.append($0) }
        }
        if shouldFail { throw AppError.network(reason: "Geçici hata") }
    }

    func open() {
        isOpen = true
        for continuation in continuations { continuation.resume() }
        continuations = []
    }

    func setFailure(_ value: Bool) { shouldFail = value }
}

private struct GatedMovieLoader: MovieDetailLoading {
    let gate: DetailRequestGate

    func loadDetails(for movie: Movie) async throws -> Movie {
        try await gate.wait()
        // Detay uçlarında çoğunlukla katalog sırası ve yetişkin işareti yoktur.
        return Movie(id: movie.id, playlistID: movie.playlistID, title: "", streamKey: "",
                     plot: "Uzak özet")
    }
}

private struct GatedSeriesLoader: SeriesDetailLoading {
    let gate: DetailRequestGate

    func loadDetails(for series: Series) async throws -> (seasons: [Season], episodes: [Episode]) {
        try await gate.wait()
        return (
            [Season(id: "s1#season#1", seriesID: series.id, number: 1, episodeCount: 1)],
            [Episode(id: "s1#episode#1", seriesID: series.id, seasonNumber: 1,
                     number: 1, title: "Bölüm", streamKey: "1")]
        )
    }
}
