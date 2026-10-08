import SwiftUI
import OctopusDomain
import OctopusPlayback

extension PlayerScreen {
    var presentedNextEpisode: Episode? {
        if isShowingNextEpisodePrompt { return viewModel.nextEpisode }
#if DEBUG
        guard previewsNextEpisodeOverlay else { return nil }
        return Episode(
            id: Episode.ID("preview-next"), seriesID: Series.ID("preview-series"),
            seasonNumber: 1, number: 2, title: "İkinci Bölüm", streamKey: "preview"
        )
#else
        return nil
#endif
    }

    func handlePlaybackStateChange(_ state: PlaybackState) {
        if state == .loading { isShowingNextEpisodePrompt = false }
        guard state == .ended, case .ready(let item) = viewModel.phase else { return }
        switch nextEpisodeSession.reachedEnd(source: item.source, hasNext: viewModel.nextEpisode != nil) {
        case .none:
            break
        case .showPrompt:
            isShowingNextEpisodePrompt = true
            hideControlsTask?.cancel()
            showsControls = true
        case .playNext:
            playNextEpisodeNow()
        }
    }

    func playNextEpisodeNow() {
        isShowingNextEpisodePrompt = false
        Task { await viewModel.playNextEpisode() }
    }

    func playNextEpisodesAutomatically() {
        nextEpisodeSession.enableAutomaticAdvance()
        playNextEpisodeNow()
    }

    func cancelNextEpisode() {
        isShowingNextEpisodePrompt = false
        showsControls = true
    }
}
