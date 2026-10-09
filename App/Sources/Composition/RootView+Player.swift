import SwiftUI
import OctopusDesignSystem
import OctopusNavigation
import FeaturePlayer

extension RootView {
    /// A separately hosted UIKit root needs these SwiftUI environments explicitly.
    @MainActor
    func playerPresenter(scenePhase: ScenePhase, revision: Int) -> some View {
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
                    .modifier(presentationEnvironment)
                    .environment(\.scenePhase, scenePhase)
                )
            },
            onDismiss: playerPresentationDidDismiss
        )
        .onChange(of: router.selectedTab) { [oldTab = router.selectedTab] newTab in
            PlayerDismissalDiagnostics.recordTabSelection(
                from: AppTab.allCases.firstIndex(of: oldTab) ?? -1,
                to: AppTab.allCases.firstIndex(of: newTab) ?? -1
            )
        }
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
