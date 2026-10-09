import Combine
import OctopusPlayback

/// The live list needs playback ownership and surface changes, not timeline ticks.
struct LivePlaybackViewState: Equatable {
    let session: PlayerController.Session?
    let state: PlaybackState
    let surfaceGeneration: Int
}

@MainActor
final class LivePlaybackObservation: ObservableObject {
    @Published private(set) var viewState: LivePlaybackViewState
    private var subscription: AnyCancellable?

    init(controller: PlayerController) {
        viewState = LivePlaybackViewState(
            session: controller.session,
            state: controller.state,
            surfaceGeneration: controller.surfaceGeneration
        )
        subscription = controller.$session
            .combineLatest(controller.$state, controller.$surfaceGeneration)
            .sink { [weak self] session, state, generation in
                let next = LivePlaybackViewState(
                    session: session, state: state, surfaceGeneration: generation
                )
                guard let self, self.viewState != next else { return }
                self.viewState = next
            }
    }
}
