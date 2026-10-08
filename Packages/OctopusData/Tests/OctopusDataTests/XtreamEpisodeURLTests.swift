import XCTest
import GRDB
import OctopusDomain
@testable import OctopusData

final class XtreamEpisodeURLTests: XCTestCase {
    func test_directSourceSurvivesDatabaseRoundTripAndWinsOverPanelURL() async throws {
        let json = """
            {"episodes":{"1":[{"id":"101","episode_num":1,"title":"Direct",
            "container_extension":"mkv","direct_source":" https://cdn.example.test/complete-film.webm?token=test "}]}}
            """
        let dto = try JSONDecoder().decode(XtreamSeriesInfoDTO.self, from: Data(json.utf8))
        let episode = try XCTUnwrap(dto.toDomain(seriesID: "p1#series#77").episodes.first)
        let database = try AppDatabase.makeInMemory()
        try await database.write { db in
            try db.execute(sql: """
                INSERT INTO playlist (id, name, kindType, createdAt, isActive)
                VALUES ('p1', 'Test', 'm3u', '2026-01-01 00:00:00', 1)
                """)
            try db.execute(sql: """
                INSERT INTO series (id, playlistId, title, streamKey, genres, cast)
                VALUES ('p1#series#77', 'p1', 'Test', '77', '[]', '[]')
                """)
            try EpisodeRecord(episode).insert(db)
        }
        let cached = try await database.read { db in
            try EpisodeRecord.fetchOne(db, key: episode.id.value)?.toDomain()
        }
        let stored = try XCTUnwrap(cached)
        let provider = try makeProvider()
        XCTAssertEqual(provider.streamURL(for: stored)?.absoluteString,
                       "https://cdn.example.test/complete-film.webm?token=test")
        XCTAssertEqual(stored.containerExtension, "mkv")
    }

    func test_invalidDirectSourceUsesValidatedExtensionWithoutGuessingMP4() throws {
        let json = """
            {"episodes":{"1":[
            {"id":"101","episode_num":1,"direct_source":"file:///private/episode.mkv","container_extension":" .MKV "},
            {"id":"102","episode_num":2,"direct_source":"/relative.mp4"},
            {"id":"103","episode_num":3,"direct_source":"https:///missing-host","container_extension":"mkv?fallback=1"},
            {"id":"104","episode_num":4,"direct_source":"https://cdn.example.test/episode"}
            ]}}
            """
        let dto = try JSONDecoder().decode(XtreamSeriesInfoDTO.self, from: Data(json.utf8))
        let episodes = dto.toDomain(seriesID: "p1#series#77").episodes
        XCTAssertEqual(episodes.count, 4)
        let provider = try makeProvider()
        XCTAssertEqual(provider.streamURL(for: episodes[0])?.path, "/series/user/password/101.mkv")
        XCTAssertNil(provider.streamURL(for: episodes[1]))
        XCTAssertNil(provider.streamURL(for: episodes[2]))
        XCTAssertEqual(provider.streamURL(for: episodes[3])?.absoluteString,
                       "https://cdn.example.test/episode")
        // Eski Codable kayıtlarında alan bulunmayabilir; cache yine çözülebilmeli.
        let encoded = try JSONEncoder().encode(episodes[0])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "directURL")
        let legacy = try JSONDecoder().decode(Episode.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.directURL)
        XCTAssertEqual(legacy.containerExtension, "mkv")
    }

    private func makeProvider() throws -> XtreamContentProvider {
        XtreamContentProvider(
            baseURL: try XCTUnwrap(URL(string: "https://panel.example.test")),
            username: "user", password: "password", playlistID: "p1",
            httpClient: StubHTTPClient(handler: { _ in Data() })
        )
    }
}
