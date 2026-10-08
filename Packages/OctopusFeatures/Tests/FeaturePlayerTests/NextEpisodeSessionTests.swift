import XCTest
import OctopusDomain
@testable import FeaturePlayer

final class NextEpisodeSessionTests: XCTestCase {
    func test_firstEndRequiresExplicitChoiceAndDuplicateEndDoesNothing() {
        var session = NextEpisodeSession()
        let source = PlaybackItem.Source.episode(Episode.ID("one"))
        XCTAssertEqual(session.reachedEnd(source: source, hasNext: true), .showPrompt)
        XCTAssertEqual(session.reachedEnd(source: source, hasNext: true), .none)
        XCTAssertFalse(session.automaticallyAdvance)
    }

    func test_cancelledOrManualChoiceDoesNotEnableAutomaticAdvance() {
        var session = NextEpisodeSession()
        _ = session.reachedEnd(source: .episode(Episode.ID("one")), hasNext: true)
        XCTAssertEqual(session.reachedEnd(source: .episode(Episode.ID("two")), hasNext: true), .showPrompt)
    }

    func test_explicitSessionConsentAdvancesFollowingEpisodesOnce() {
        var session = NextEpisodeSession()
        _ = session.reachedEnd(source: .episode(Episode.ID("one")), hasNext: true)
        session.enableAutomaticAdvance()
        XCTAssertEqual(session.reachedEnd(source: .episode(Episode.ID("two")), hasNext: true), .playNext)
        XCTAssertEqual(session.reachedEnd(source: .episode(Episode.ID("two")), hasNext: true), .none)
    }

    func test_newPlayerSessionAlwaysRequiresConsentAgain() {
        var previous = NextEpisodeSession()
        previous.enableAutomaticAdvance()
        var reopened = NextEpisodeSession()
        XCTAssertEqual(reopened.reachedEnd(source: .episode(Episode.ID("one")), hasNext: true), .showPrompt)
    }

    func test_movieLiveAndLastEpisodeNeverAdvance() {
        var session = NextEpisodeSession()
        session.enableAutomaticAdvance()
        XCTAssertEqual(session.reachedEnd(source: .movie(Movie.ID("movie")), hasNext: true), .none)
        XCTAssertEqual(session.reachedEnd(source: .liveChannel(Channel.ID("live")), hasNext: true), .none)
        XCTAssertEqual(session.reachedEnd(source: .episode(Episode.ID("last")), hasNext: false), .none)
    }
}
