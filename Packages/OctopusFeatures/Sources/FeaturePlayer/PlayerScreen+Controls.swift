import SwiftUI
import OctopusDomain
import OctopusDesignSystem
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
            PlayerGestureSurface(
                isEnabled: !isControlsLocked,
                isLive: item.isLive,
                volume: controller.volume,
                onSingleTap: toggleControls,
                onSkip: handleGestureSkip,
                onVolume: handleGestureVolume,
                onBrightness: handleGestureBrightness
            )

            if isControlsLocked {
                PlayerLockControl(isLocked: true) {
                    isControlsLocked = false
                    scheduleControlsHide()
                }
                .padding(.leading, Theme.Spacing.md)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else if showsControls {
                PlayerControlsOverlay(
                    title: item.title,
                    subtitle: item.subtitle,
                    isLive: item.isLive,
                    state: controller.state,
                    time: controller.time,
                    hasTracks: hasSelectableTracks,
                    showsAirPlay: controller.supportsAirPlay,
                    showsPictureInPicture: PictureInPicturePolicy.canShowButton(
                        for: item,
                        engineIsReady: controller.canUsePictureInPicture
                            || previewsPictureInPictureButton
                    ),
                    canZap: viewModel.canZap,
                    videoFit: controller.videoFit,
                    rate: controller.rate,
                    onClose: close,
                    onTogglePlay: {
                        Task { await controller.togglePlayPause() }
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
                        showsControls = false
                        isShowingTracks = true
                    },
                    onToggleFit: {
                        controller.toggleVideoFit()
                        scheduleControlsHide()
                    },
                    onSetRate: { rate in
                        controller.setRate(rate)
                        scheduleControlsHide()
                    },
                    onPictureInPicture: {
                        controller.startPictureInPicture()
                        // Küçük pencereye geçilirken denetimler ekranda
                        // asılı kalmasın.
                        showsControls = false
                    },
                    onLock: {
                        hideControlsTask?.cancel()
                        isControlsLocked = true
                        showsControls = false
                    },
                    onShowLivePanel: {
                        hideControlsTask?.cancel()
                        isShowingLivePanel = true
                    },
                    onZap: { step in
                        Task { await viewModel.zap(by: step) }
                        // Kanal değişince denetimler açık kalsın: kullanıcı
                        // genelde arka arkaya birkaç kanal geçiyor.
                        scheduleControlsHide()
                    }
                )
                .transition(.opacity)
            }

            if let episode = presentedNextEpisode,
               let countdown = presentedNextEpisodeCountdown {
                NextEpisodeOverlay(
                    episode: episode,
                    countdown: countdown,
                    onPlay: playNextEpisodeNow,
                    onCancel: cancelNextEpisode
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            if let gestureNotice {
                PlayerGestureNoticeView(notice: gestureNotice)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showsControls)
    }

    var hasSelectableTracks: Bool {
        controller.audioTracks.count > 1 || !controller.subtitleTracks.isEmpty
    }

    // MARK: - Denetim görünürlüğü

    func toggleControls() {
        guard !isControlsLocked else { return }
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

        // Ekran görüntüsü testi gerçek video yüklendikten sonra çalışır.
        // Süreye güvenmek yerine DEBUG kapısında görünürlüğü kesinleştir.
        guard !keepsControlsVisible else { return }

        hideControlsTask = Task {
            try? await Task.sleep(for: autoHideDelay)
            guard !Task.isCancelled, controller.state == .playing else { return }
            showsControls = false
        }
    }

}
