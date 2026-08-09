import SwiftUI
import OctopusDomain
import OctopusPlayback

/// Oynatıcı denetimlerinin bağlanması ve görünürlüğü.
///
/// `PlayerScreen`'den ayrıldı: ekran dosyası 200 satır kuralını aşıyordu
/// (bkz. CLAUDE.md). Buradaki her şey aynı görünümün parçası — ayrı bir
/// tip değil, yalnızca ayrı bir dosya.
extension PlayerScreen {

    func controlsLayer(_ item: PlaybackItem) -> some View {
        ZStack {
            // Dokunma alanı tüm ekran: kullanıcı düğmeyi aramak zorunda kalmasın.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { toggleControls() }

            if showsControls {
                PlayerControlsOverlay(
                    title: item.title,
                    subtitle: item.subtitle,
                    isLive: item.isLive,
                    state: controller.state,
                    time: controller.time,
                    hasTracks: hasSelectableTracks,
                    showsAirPlay: controller.supportsAirPlay,
                    videoFit: controller.videoFit,
                    onClose: close,
                    onTogglePlay: {
                        controller.togglePlayPause()
                        scheduleControlsHide()
                    },
                    onSkip: { delta in
                        Task { await controller.skip(by: delta) }
                        scheduleControlsHide()
                    },
                    onSeek: { position in
                        Task { await controller.seek(to: position) }
                        scheduleControlsHide()
                    },
                    onShowTracks: {
                        hideControlsTask?.cancel()
                        isShowingTracks = true
                    },
                    onToggleFit: {
                        controller.toggleVideoFit()
                        scheduleControlsHide()
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showsControls)
    }

    var hasSelectableTracks: Bool {
        controller.audioTracks.count > 1 || !controller.subtitleTracks.isEmpty
    }

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

    // MARK: - Denetim görünürlüğü

    func toggleControls() {
        showsControls.toggle()
        if showsControls {
            scheduleControlsHide()
        } else {
            hideControlsTask?.cancel()
        }
    }

    /// Denetimleri belirli bir süre sonra gizler.
    ///
    /// ⚠️ Duraklatılmışken gizlenmez: ekranda hiçbir ipucu kalmaz ve
    /// kullanıcı videonun donduğunu sanır.
    func scheduleControlsHide() {
        hideControlsTask?.cancel()
        showsControls = true

        hideControlsTask = Task {
            try? await Task.sleep(for: autoHideDelay)
            guard !Task.isCancelled, controller.state == .playing else { return }
            showsControls = false
        }
    }
}
