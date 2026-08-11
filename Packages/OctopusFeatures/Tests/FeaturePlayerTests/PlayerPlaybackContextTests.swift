import XCTest
import OctopusDomain
@testable import FeaturePlayer

@MainActor
final class PlayerPlaybackContextTests: XCTestCase {

    private let seriesID = Series.ID("series-1")

    func test_followingEpisodeContinuesInSameSeason() {
        let current = episode(id: "e1", season: 1, number: 1)
        let result = PlayerViewModel.followingEpisode(
            after: current,
            in: [episode(id: "e3", season: 2, number: 1),
                 episode(id: "e2", season: 1, number: 2), current]
        )

        XCTAssertEqual(result?.id, Episode.ID("e2"))
    }

    func test_followingEpisodeMovesToNextSeason() {
        let current = episode(id: "e2", season: 1, number: 2)
        let result = PlayerViewModel.followingEpisode(
            after: current,
            in: [episode(id: "e3", season: 2, number: 1), current]
        )

        XCTAssertEqual(result?.id, Episode.ID("e3"))
    }

    func test_lastEpisodeHasNoFollowingEpisode() {
        let current = episode(id: "last", season: 2, number: 8)
        XCTAssertNil(PlayerViewModel.followingEpisode(after: current, in: [current]))
    }

    func test_guideFindsCurrentAndFollowingProgram() {
        let now = Date(timeIntervalSince1970: 10_000)
        let current = program(id: "now", start: now.addingTimeInterval(-60), end: now.addingTimeInterval(60))
        let following = program(id: "next", start: now.addingTimeInterval(60), end: now.addingTimeInterval(120))

        let result = PlayerViewModel.guidePrograms(at: now, programs: [following, current])

        XCTAssertEqual(result.current?.id, EPGProgram.ID("now"))
        XCTAssertEqual(result.following?.id, EPGProgram.ID("next"))
    }

    private func episode(id: String, season: Int, number: Int) -> Episode {
        Episode(
            id: Episode.ID(id),
            seriesID: seriesID,
            seasonNumber: season,
            number: number,
            title: "Bölüm \(number)",
            streamKey: id
        )
    }

    private func program(id: String, start: Date, end: Date) -> EPGProgram {
        EPGProgram(
            id: EPGProgram.ID(id),
            epgChannelID: "channel",
            title: id,
            startDate: start,
            endDate: end
        )
    }
}
