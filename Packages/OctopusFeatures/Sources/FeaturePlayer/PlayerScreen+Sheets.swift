import SwiftUI
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
            currentProgram: viewModel.currentProgram,
            followingProgram: viewModel.followingProgram,
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
}
