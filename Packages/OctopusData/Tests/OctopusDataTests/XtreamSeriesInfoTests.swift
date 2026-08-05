import XCTest
import OctopusDomain
@testable import OctopusData

/// `get_series_info` çözümlemesi ve dizi ağacının yerelde saklanması.
final class XtreamSeriesInfoTests: XCTestCase {

    private let seriesID = Series.ID("p1#series#77")

    private func decode(_ json: String) throws -> XtreamSeriesInfoDTO {
        try JSONDecoder().decode(XtreamSeriesInfoDTO.self, from: Data(json.utf8))
    }

    // MARK: - Bölüm ağacı biçimleri

    func test_parsesEpisodesKeyedBySeason() throws {
        let dto = try decode("""
            {"seasons":[{"season_number":1,"name":"1. Sezon","episode_count":2}],
             "episodes":{"1":[
               {"id":"101","episode_num":1,"title":"İlk","container_extension":"mkv"},
               {"id":"102","episode_num":2,"title":"İkinci"}
             ]}}
            """)

        let result = dto.toDomain(seriesID: seriesID)

        XCTAssertEqual(result.seasons.map(\.number), [1])
        XCTAssertEqual(result.seasons.first?.name, "1. Sezon")
        XCTAssertEqual(result.episodes.map(\.title), ["İlk", "İkinci"])
        XCTAssertEqual(result.episodes.first?.containerExtension, "mkv")
        XCTAssertEqual(result.episodes.last?.containerExtension, "mp4", "Varsayılan uzantı")
    }

    func test_parsesFlatEpisodeArray() throws {
        // Bazı paneller sezonsuz dizilerde düz dizi döndürüyor.
        let dto = try decode("""
            {"episodes":[{"id":"1","episode_num":1,"title":"Tek Bölüm"}]}
            """)

        let result = dto.toDomain(seriesID: seriesID)

        XCTAssertEqual(result.episodes.count, 1)
        XCTAssertEqual(result.episodes.first?.seasonNumber, 1, "Sezonsuz içerik 1. sezona düşer")
        XCTAssertEqual(result.seasons.map(\.number), [1])
    }

    func test_multipleSeasonsAreSortedByNumberThenEpisode() throws {
        let dto = try decode("""
            {"episodes":{
              "2":[{"id":"201","episode_num":2,"title":"S2B2"},
                   {"id":"200","episode_num":1,"title":"S2B1"}],
              "1":[{"id":"101","episode_num":1,"title":"S1B1"}]
            }}
            """)

        let result = dto.toDomain(seriesID: seriesID)

        XCTAssertEqual(result.episodes.map(\.title), ["S1B1", "S2B1", "S2B2"])
        XCTAssertEqual(result.seasons.map(\.number), [1, 2])
    }

    // MARK: - Eksik veri toleransı

    func test_missingSeasonListIsDerivedFromEpisodes() throws {
        // Panel sezon listesi göndermezse dizi "sezonsuz" görünüp açılamazdı.
        let dto = try decode("""
            {"episodes":{"3":[{"id":"301","episode_num":1,"title":"S3B1"}]}}
            """)

        let result = dto.toDomain(seriesID: seriesID)

        XCTAssertEqual(result.seasons.map(\.number), [3])
        XCTAssertEqual(result.seasons.first?.episodeCount, 1)
    }

    func test_seasonsWithoutEpisodesAreHidden() throws {
        // Boş sezona tıklayan kullanıcı boş liste görür; hiç göstermemek daha iyi.
        let dto = try decode("""
            {"seasons":[{"season_number":1},{"season_number":2}],
             "episodes":{"1":[{"id":"101","episode_num":1,"title":"Var"}]}}
            """)

        let result = dto.toDomain(seriesID: seriesID)
        XCTAssertEqual(result.seasons.map(\.number), [1], "Bölümsüz sezon listelenmemeli")
    }

    func test_episodeWithoutIDIsSkipped() throws {
        // Akış anahtarı olmadan bölüm oynatılamaz.
        let dto = try decode("""
            {"episodes":{"1":[
              {"episode_num":1,"title":"Kimliksiz"},
              {"id":"102","episode_num":2,"title":"Geçerli"}
            ]}}
            """)

        let result = dto.toDomain(seriesID: seriesID)
        XCTAssertEqual(result.episodes.map(\.title), ["Geçerli"])
    }

    func test_episodeWithoutTitleGetsNumberedName() throws {
        let dto = try decode("""
            {"episodes":{"1":[{"id":"107","episode_num":7}]}}
            """)

        let result = dto.toDomain(seriesID: seriesID)
        XCTAssertEqual(result.episodes.first?.title, "Bölüm 7")
    }

    func test_episodeInfoIsCarried() throws {
        let dto = try decode("""
            {"episodes":{"1":[{"id":"101","episode_num":1,"title":"Bölüm",
              "info":{"plot":"Özet","duration_secs":2700,
                      "movie_image":"http://img.example.com/still.jpg"}}]}}
            """)

        let episode = try XCTUnwrap(dto.toDomain(seriesID: seriesID).episodes.first)
        XCTAssertEqual(episode.plot, "Özet")
        XCTAssertEqual(episode.durationSeconds, 2_700)
        XCTAssertEqual(episode.stillURL?.absoluteString, "http://img.example.com/still.jpg")
    }

    func test_episodeOwnSeasonFieldWins() throws {
        // Sözlük anahtarı ile bölümün kendi alanı çelişirse bölüme güvenilir.
        let dto = try decode("""
            {"episodes":{"1":[{"id":"501","episode_num":1,"season":5,"title":"Aslında S5"}]}}
            """)

        let result = dto.toDomain(seriesID: seriesID)
        XCTAssertEqual(result.episodes.first?.seasonNumber, 5)
        XCTAssertEqual(result.seasons.map(\.number), [5])
    }

    func test_shortLabelFormatsSeasonAndEpisode() throws {
        let dto = try decode("""
            {"episodes":{"2":[{"id":"207","episode_num":7,"title":"Bölüm"}]}}
            """)

        let episode = try XCTUnwrap(dto.toDomain(seriesID: seriesID).episodes.first)
        XCTAssertEqual(episode.shortLabel, "S02B07")
    }
}

/// Ağacın yerelde saklanması ve tekrar çekilmemesi.
final class SeriesDetailCacheTests: XCTestCase {

    private var database: AppDatabase!
    private var loader: SpyDetailLoader!
    private var repository: GRDBSeriesRepository!

    override func setUp() async throws {
        database = try AppDatabase.makeInMemory()
        loader = SpyDetailLoader()
        repository = GRDBSeriesRepository(database: database, detailLoader: loader)

        try await database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO playlist (id, name, kindType, createdAt, isActive)
                    VALUES ('p1', 'Kaynak', 'm3u', '2026-01-01 00:00:00', 1)
                    """
            )
            try db.execute(
                sql: """
                    INSERT INTO series (id, playlistId, title, streamKey, genres, cast)
                    VALUES ('p1#series#77', 'p1', 'Dizi', '77', '[]', '[]')
                    """
            )
        }
    }

    func test_detailsAreStoredAndReadable() async throws {
        try await repository.loadDetails(id: "p1#series#77")

        let seasons = try await repository.seasons(seriesID: "p1#series#77")
        XCTAssertEqual(seasons.map(\.number), [1])

        let episodes = try await repository.episodes(seriesID: "p1#series#77", seasonNumber: 1)
        XCTAssertEqual(episodes.map(\.title), ["Bölüm 1", "Bölüm 2"])
    }

    func test_secondCallUsesCache() async throws {
        // Referans projede get_series_info her açılışta çağrılıyordu;
        // ağır bir istek ve kullanıcı her seferinde bekliyordu.
        try await repository.loadDetails(id: "p1#series#77")
        try await repository.loadDetails(id: "p1#series#77")

        XCTAssertEqual(loader.callCount, 1, "Ağaç bir kez çekilmeli")
    }

    func test_invalidateForcesRefetch() async throws {
        try await repository.loadDetails(id: "p1#series#77")
        try await repository.invalidateDetails(id: "p1#series#77")
        try await repository.loadDetails(id: "p1#series#77")

        XCTAssertEqual(loader.callCount, 2)
    }

    func test_refetchReplacesTreeInsteadOfDuplicating() async throws {
        try await repository.loadDetails(id: "p1#series#77")
        try await repository.invalidateDetails(id: "p1#series#77")

        // Panelde bir bölüm kaldırılmış.
        loader.episodeCount = 1
        try await repository.loadDetails(id: "p1#series#77")

        let episodes = try await repository.episodes(seriesID: "p1#series#77", seasonNumber: 1)
        XCTAssertEqual(episodes.count, 1, "Eski bölümler silinmeli, kopya oluşmamalı")
    }

    func test_missingSeriesThrows() async {
        do {
            try await repository.loadDetails(id: "yok")
            XCTFail("Var olmayan dizi hata vermeli")
        } catch {
            XCTAssertEqual(error as? AppError, .notFound)
        }
    }
}

private final class SpyDetailLoader: SeriesDetailLoading, @unchecked Sendable {

    private(set) var callCount = 0
    var episodeCount = 2

    func loadDetails(
        for series: Series
    ) async throws -> (seasons: [Season], episodes: [Episode]) {
        callCount += 1

        let episodes = (1...episodeCount).map { number in
            Episode(
                id: Episode.ID("\(series.id.value)#e#\(number)"),
                seriesID: series.id,
                seasonNumber: 1,
                number: number,
                title: "Bölüm \(number)",
                streamKey: "\(number)"
            )
        }
        let season = Season(
            id: Season.ID("\(series.id.value)#s1"),
            seriesID: series.id,
            number: 1,
            episodeCount: episodes.count
        )
        return ([season], episodes)
    }
}
