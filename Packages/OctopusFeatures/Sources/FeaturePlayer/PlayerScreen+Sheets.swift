import SwiftUI
import Foundation
import OctopusDomain

extension PlayerScreen {

    @ViewBuilder
    var trackPicker: some View {
        PlayerTrackPicker(
            audioTracks: controller.audioTracks,
            subtitleTracks: controller.subtitleTracks,
            selectedAudio: controller.selectedAudioTrack,
            selectedSubtitle: controller.selectedSubtitleTrack,
            onSelect: controller.select
        )
    }

    var livePanel: some View {
        PlayerLivePanel(
            channels: viewModel.liveChannels,
            currentSource: currentLiveChannelID,
            currentProgram: displayedCurrentProgram,
            followingProgram: displayedFollowingProgram,
            onSelect: { channel in
                isShowingLivePanel = false
                Task { await viewModel.play(channel: channel) }
            }
        )
    }

    private var currentLiveChannelID: Channel.ID? {
        guard case .ready(let item) = viewModel.phase,
              case .liveChannel(let id) = item.source else { return nil }
        return id
    }

    private var displayedCurrentProgram: EPGProgram? {
        viewModel.currentProgram ?? previewProgram(
            id: "preview-current",
            title: "Ana Haber",
            startsIn: -20 * 60,
            endsIn: 25 * 60
        )
    }

    private var displayedFollowingProgram: EPGProgram? {
        viewModel.followingProgram ?? previewProgram(
            id: "preview-next",
            title: "Günün Gündemi",
            startsIn: 25 * 60,
            endsIn: 75 * 60
        )
    }

    private func previewProgram(
        id: String,
        title: String,
        startsIn: TimeInterval,
        endsIn: TimeInterval
    ) -> EPGProgram? {
#if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-previewLivePanel") else { return nil }
        let now = Date.now
        return EPGProgram(
            id: EPGProgram.ID(id),
            epgChannelID: "preview",
            title: title,
            startDate: now.addingTimeInterval(startsIn),
            endDate: now.addingTimeInterval(endsIn)
        )
#else
        return nil
#endif
    }
}
