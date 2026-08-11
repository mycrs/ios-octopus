import XCTest
import OctopusDomain
import OctopusPlayback
@testable import FeaturePlayer

@MainActor
final class PlayerNextEpisodeViewModelTests: XCTestCase {

    func test_playNextEpisodeResolvesFollowingItemAndUpdatesQueue() async {
        let seriesID = Series.ID("series-1")
        let first = episode(id: "e1", seriesID: seriesID, number: 1)
        let second = episode(id: "e2", seriesID: seriesID, number: 2)
        let repository = StubSeries(episodes: [second, first])
        let dependencies = PlayerDependencies(
            resolver: PlaybackEngineResolver(native: { NullPlaybackEngine() }),
            streams: StubStreams(),
            progress: StubProgress(),
            history: StubHistory(),
            channels: StubChannels(channels: []),
            vod: StubVOD(),
            series: repository
        )
        let viewModel = PlayerViewModel(
            dependencies: dependencies,
            source: .episode(first.id)
        )

        await viewModel.resolve()
        XCTAssertEqual(viewModel.nextEpisode?.id, second.id)

        await viewModel.playNextEpisode()

        guard case .ready(let item) = viewModel.phase else {
            return XCTFail("Sonraki bölüm çözümlenemedi")
        }
        XCTAssertEqual(item.source, .episode(second.id))
        XCTAssertNil(viewModel.nextEpisode)
    }

    private func episode(
        id: String,
        seriesID: Series.ID,
        number: Int
    ) -> Episode {
        Episode(
            id: Episode.ID(id),
            seriesID: seriesID,
            seasonNumber: 1,
            number: number,
            title: "Bölüm \(number)",
            streamKey: id
        )
    }
}
