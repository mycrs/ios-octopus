import SwiftUI
import OctopusDomain
import OctopusPlayback

extension PlayerScreen {

    var presentedNextEpisode: Episode? {
        if let nextEpisode = viewModel.nextEpisode { return nextEpisode }
#if DEBUG
        guard previewsNextEpisodeOverlay else { return nil }
        return Episode(
            id: Episode.ID("preview-next"),
            seriesID: Series.ID("preview-series"),
            seasonNumber: 1,
            number: 2,
            title: "İkinci Bölüm",
            streamKey: "preview"
        )
#else
        return nil
#endif
    }

    var presentedNextEpisodeCountdown: Int? {
        if let nextEpisodeCountdown { return nextEpisodeCountdown }
#if DEBUG
        return previewsNextEpisodeOverlay ? 8 : nil
#else
        return nil
#endif
    }

    func handlePlaybackStateChange(_ state: PlaybackState) {
        guard state == .ended, viewModel.nextEpisode != nil else {
            if state != .ended {
                nextEpisodeTask?.cancel()
                nextEpisodeTask = nil
                nextEpisodeCountdown = nil
            }
            return
        }

        guard nextEpisodeTask == nil else { return }
        nextEpisodeCountdown = 8
        nextEpisodeTask = Task { @MainActor in
            for remaining in stride(from: 7, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                nextEpisodeCountdown = remaining
            }
            await viewModel.playNextEpisode()
            nextEpisodeTask = nil
            nextEpisodeCountdown = nil
        }
    }

    func playNextEpisodeNow() {
        nextEpisodeTask?.cancel()
        nextEpisodeTask = nil
        nextEpisodeCountdown = nil
        Task { await viewModel.playNextEpisode() }
    }

    func cancelNextEpisode() {
        nextEpisodeTask?.cancel()
        nextEpisodeTask = nil
        nextEpisodeCountdown = nil
        showsControls = true
    }
}
