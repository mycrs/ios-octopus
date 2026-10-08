import SwiftUI
import OctopusDomain
import OctopusDesignSystem
import OctopusNavigation
import OctopusPlayback

extension PlayerScreen {
    var isCurrentPlayerPresentation: Bool { router.player?.id == presentation.id }

    /// Adres üretilemedi — sorun oynatıcıdan önce.
    func resolveFailure(_ message: String) -> some View {
        EmptyStateView(
            icon: "exclamationmark.triangle",
            title: "Yayın adresi alınamadı",
            message: message,
            actionTitle: "Kapat",
            action: close
        )
    }

    /// Adres üretildi ama açılamadı — sorun akışta ya da motorda.
    /// İçeriği `PlaybackErrorView` çiziyor.
    func playbackFailure(_ error: AppError, item: PlaybackItem) -> some View {
        PlaybackErrorView(
            error: error,
            item: item,
            failureKind: controller.failureKind,
            onRetry: {
                Task {
                    guard router.player?.id == presentation.id else { return }
                    await controller.start(item) { ownedSession = $0 }
                }
            },
            onClose: close,
            onPreviousChannel: hasChannelContext(item) && viewModel.canZap
                ? { Task { await viewModel.zap(by: -1) } }
                : nil,
            onNextChannel: hasChannelContext(item) && viewModel.canZap
                ? { Task { await viewModel.zap(by: 1) } }
                : nil
        )
    }

    func close() {
        hideControlsTask?.cancel()
        guard router.player?.id == presentation.id else { return }
        ownedSession = controller.session
        releasePlaybackIfNeeded()
        router.dismissPlayer(ifPresented: presentation.id)
    }

    func hasChannelContext(_ item: PlaybackItem) -> Bool {
        if case .liveChannel = item.source { return true }
        return false
    }

    func releasePlaybackIfNeeded() {
        guard let session = ownedSession, controller.session == session else { return }
        if case .liveChannel = session.source,
           router.canReturnToLivePreview(from: presentation) {
            return
        }
        controller.stop(ifCurrent: session)
    }
}
