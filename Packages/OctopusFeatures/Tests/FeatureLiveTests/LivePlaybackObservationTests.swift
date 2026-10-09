import Combine
import XCTest
import OctopusDomain
import OctopusPlayback
@testable import FeatureLive

@MainActor
final class LivePlaybackObservationTests: XCTestCase {
    func test_initialProjectionUsesAlreadyPlayingController() async {
        let engine = LiveObservationTestEngine()
        let controller = makeController(engine)
        await controller.start(item("first"))
        await waitUntil { controller.state == .playing }
        let observation = LivePlaybackObservation(controller: controller)

        XCTAssertEqual(observation.viewState.session, controller.session)
        XCTAssertEqual(observation.viewState.state, .playing)
        XCTAssertEqual(observation.viewState.surfaceGeneration, controller.surfaceGeneration)
        XCTAssertEqual(engine.loadCount, 1)
        XCTAssertEqual(engine.playCount, 1)
        await controller.finish()
    }

    func test_timeOnlyEventsDoNotPublishLiveViewState() async {
        let engine = LiveObservationTestEngine()
        let controller = makeController(engine)
        await controller.start(item("first"))
        await waitUntil { controller.state == .playing }
        let observation = LivePlaybackObservation(controller: controller)
        let initial = observation.viewState
        var published: [LivePlaybackViewState] = []
        let subscription = observation.$viewState.dropFirst().sink { published.append($0) }
        defer { subscription.cancel() }

        for second in 1...64 {
            engine.emit(.timeChanged(PlaybackTime(current: Double(second), duration: nil, bufferedUpTo: 64)))
        }
        await waitUntil { controller.time.current == 64 }
        XCTAssertTrue(published.isEmpty)
        XCTAssertEqual(observation.viewState, initial)
        await controller.finish()
    }

    func test_stateChangesPublishButIdenticalStatesDoNot() async {
        let engine = LiveObservationTestEngine()
        let controller = makeController(engine)
        await controller.start(item("first"))
        await waitUntil { controller.state == .playing }
        let observation = LivePlaybackObservation(controller: controller)
        var published: [LivePlaybackViewState] = []
        let subscription = observation.$viewState.dropFirst().sink { published.append($0) }
        defer { subscription.cancel() }

        engine.emit(.stateChanged(.buffering))
        await waitUntil { observation.viewState.state == .buffering }
        XCTAssertTrue(observation.viewState.state.showsSpinner)
        engine.emit(.stateChanged(.buffering))
        engine.emit(.timeChanged(PlaybackTime(current: 77, duration: nil, bufferedUpTo: 77)))
        await waitUntil { controller.time.current == 77 }
        XCTAssertEqual(published.count, 1)
        controller.pause()
        await waitUntil { observation.viewState.state == .paused }
        XCTAssertFalse(observation.viewState.state.showsSpinner)
        controller.play()
        await waitUntil { observation.viewState.state == .playing }
        engine.emit(.stateChanged(.failed(.notFound)))
        await waitUntil { observation.viewState.state == .failed(.notFound) }
        await controller.finish()
        XCTAssertEqual(observation.viewState.state, .idle)
    }

    func test_channelSessionChangeAndReleaseRemainObservable() async throws {
        let engine = LiveObservationTestEngine()
        let controller = makeController(engine)
        await controller.start(item("first"))
        await waitUntil { controller.state == .playing }
        let first = try XCTUnwrap(controller.session)
        let generation = controller.surfaceGeneration
        let observation = LivePlaybackObservation(controller: controller)

        await controller.start(item("second"))
        await waitUntil { observation.viewState.session == controller.session && controller.state == .playing }
        let second = try XCTUnwrap(controller.session)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(observation.viewState.session, second)
        XCTAssertEqual(engine.loadCount, 2)
        XCTAssertEqual(engine.teardownCount, 0)
        XCTAssertEqual(observation.viewState.surfaceGeneration, generation)
        await controller.finish()
        XCTAssertNil(observation.viewState.session)
        XCTAssertEqual(observation.viewState.state, .idle)
    }

    func test_surfaceReplacementPublishesWithSameSessionStateAndIdentifier() async throws {
        let native = LiveObservationTestEngine()
        let fallback = LiveObservationTestEngine()
        let controller = makeController(native, fallback: fallback)
        await controller.start(item("first"))
        await waitUntil { controller.state == .playing }
        let session = try XCTUnwrap(controller.session)
        let observation = LivePlaybackObservation(controller: controller)
        let generation = observation.viewState.surfaceGeneration

        native.emit(.unrecoverableFailure(.playbackFailed(reason: "decoder"), kind: .decoder))
        await waitUntil {
            fallback.playCount == 1 && observation.viewState.surfaceGeneration > generation
                && observation.viewState.state == .playing && controller.state == .playing
        }
        XCTAssertEqual(controller.engineIdentifier, native.identifier)
        XCTAssertEqual(observation.viewState.session, session)
        XCTAssertEqual(observation.viewState.state, .playing)
        XCTAssertEqual(observation.viewState.surfaceGeneration, controller.surfaceGeneration)
        XCTAssertTrue(controller.makeVideoView() === fallback.surface)
        XCTAssertEqual(native.teardownCount, 1)
        await controller.finish()
    }

    func test_releasingObservationCancelsWithoutStoppingSharedPlayback() async throws {
        let engine = LiveObservationTestEngine()
        let controller = makeController(engine)
        await controller.start(item("first"))
        await waitUntil { controller.state == .playing }
        let session = try XCTUnwrap(controller.session)
        var observation: LivePlaybackObservation? = LivePlaybackObservation(controller: controller)
        weak var released = observation
        var publications = 0
        let subscription = try XCTUnwrap(observation).$viewState.dropFirst().sink { _ in publications += 1 }
        defer { subscription.cancel() }
        observation = nil

        XCTAssertNil(released)
        engine.emit(.stateChanged(.buffering))
        await waitUntil { controller.state == .buffering }
        XCTAssertEqual(publications, 0)
        XCTAssertEqual(controller.session, session)
        XCTAssertEqual(engine.teardownCount, 0)
        await controller.finish()
    }

    private func makeController(
        _ native: LiveObservationTestEngine, fallback: LiveObservationTestEngine? = nil
    ) -> PlayerController {
        let fallbackFactory: PlaybackEngineResolver.EngineFactory? = fallback.map { engine in { engine } }
        return PlayerController(
            resolver: PlaybackEngineResolver(native: { native }, fallback: fallbackFactory),
            progress: LiveStubProgress(), history: LiveObservationTestHistory(), setScreenAwake: { _ in }
        )
    }

    private func item(_ id: String) -> PlaybackItem {
        PlaybackItem(source: .liveChannel(Channel.ID(id)),
                     url: URL(string: "https://example.invalid/\(id).mp4") ?? URL(fileURLWithPath: "/"),
                     title: "Example", isLive: true)
    }

    private func waitUntil(file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) async {
        for _ in 0..<300 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Expected real controller event was not received", file: file, line: line)
    }
}
