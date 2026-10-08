import SwiftUI
import OctopusDesignSystem
import FeaturePlayer

extension RootView {
    /// A separately hosted UIKit root needs these SwiftUI environments explicitly.
    @MainActor
    func playerPresenter(scenePhase: ScenePhase, revision: Int) -> PlayerFullscreenPresenter {
        PlayerFullscreenPresenter(
            presentation: router.player,
            reconciliationRevision: revision,
            makeContent: { presentation in
                AnyView(
                    PlayerScreen(
                        presentation: presentation,
                        dependencies: container.makePlayerDependencies()
                    )
                    .id(presentation.id)
                    .environmentObject(router)
                    .environmentObject(container.themeController)
                    .environmentObject(container.playbackPreferences)
                    .environment(\.locale, language.locale)
                    .environment(\.scenePhase, scenePhase)
                    .environment(\.brandColor, container.themeController.accent)
                    .tint(container.themeController.accent)
                )
            },
            onDismiss: playerPresentationDidDismiss
        )
    }

    /// UIKit may dismiss while SwiftUI still has the presentation registered.
    /// Stop only that current presentation's session, or hand it to Live.
    @MainActor
    private func playerPresentationDidDismiss(_ id: String) {
        guard let presentation = router.player, presentation.id == id else { return }
        if let session = container.playbackController.session {
            switch session.source {
            case .liveChannel where router.canReturnToLivePreview(from: presentation):
                break
            default:
                container.playbackController.stop(ifCurrent: session)
            }
        }
        router.dismissPlayer(ifPresented: id)
    }
}
