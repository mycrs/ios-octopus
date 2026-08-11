import XCTest
import Foundation
import OctopusDomain
@testable import OctopusPlayback

final class PictureInPicturePolicyTests: XCTestCase {

    func test_movieShowsButtonWhenEngineIsReady() {
        XCTAssertTrue(
            PictureInPicturePolicy.canShowButton(
                for: makeItem(source: .movie(Movie.ID("movie-1"))),
                engineIsReady: true
            )
        )
    }

    func test_episodeShowsButtonWhenEngineIsReady() {
        XCTAssertTrue(
            PictureInPicturePolicy.canShowButton(
                for: makeItem(source: .episode(Episode.ID("episode-1"))),
                engineIsReady: true
            )
        )
    }

    func test_liveChannelShowsButtonWhenEngineIsReady() {
        XCTAssertTrue(
            PictureInPicturePolicy.canShowButton(
                for: makeItem(source: .liveChannel(Channel.ID("channel-1"))),
                engineIsReady: true
            )
        )
    }

    func test_unreadyEngineHidesButton() {
        XCTAssertFalse(
            PictureInPicturePolicy.canShowButton(
                for: makeItem(source: .movie(Movie.ID("movie-1"))),
                engineIsReady: false
            )
        )
    }

    func test_automaticStartIsDisabled() {
        XCTAssertFalse(PictureInPicturePolicy.startsAutomaticallyFromInline)
    }

    private func makeItem(source: PlaybackItem.Source) -> PlaybackItem {
        let isLive: Bool
        if case .liveChannel = source {
            isLive = true
        } else {
            isLive = false
        }

        return PlaybackItem(
            source: source,
            url: URL(fileURLWithPath: "/tmp/video.m3u8"),
            title: "Test",
            isLive: isLive
        )
    }
}
