import SwiftUI
import Foundation
import OctopusDomain
import OctopusDesignSystem

extension PlayerScreen {

    @ViewBuilder
    func trackPicker(_ focus: PlayerTrackPicker.Focus) -> some View {
        PlayerTrackPicker(
            focus: focus,
            audioTracks: controller.audioTracks,
            subtitleTracks: controller.subtitleTracks,
            selectedAudio: controller.selectedAudioTrack,
            selectedSubtitle: controller.selectedSubtitleTrack,
            onSelect: controller.select
        )
    }

    var livePanel: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Video açık ve net kalır; dışarı dokunmak yalnızca listeyi kapatır.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: dismissLivePanel)
                    .accessibilityHidden(true)
                PlayerLivePanel(
                    channels: viewModel.liveChannels,
                    currentSource: currentLiveChannelID,
                    currentProgram: displayedCurrentProgram,
                    followingProgram: displayedFollowingProgram,
                    onSelect: { channel in
                        dismissLivePanel()
                        guard channel.id != currentLiveChannelID else { return }
                        Task { await viewModel.play(channel: channel) }
                    },
                    onDismiss: dismissLivePanel
                )
                .frame(width: livePanelWidth(in: geometry.size))
                .padding(.vertical, Theme.Spacing.sm)
                .padding(.leading, Theme.Spacing.sm)
            }
        }
    }

    private func dismissLivePanel() {
        isShowingLivePanel = false
        scheduleControlsHide()
    }

    private func livePanelWidth(in size: CGSize) -> CGFloat {
        if size.width > size.height {
            return min(min(max(size.width * 0.45, 240), 360), size.width * 0.8)
        }
        return min(size.width * 0.88, 360)
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
