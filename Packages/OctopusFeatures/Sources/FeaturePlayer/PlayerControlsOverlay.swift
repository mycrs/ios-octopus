import SwiftUI
import OctopusDesignSystem
import OctopusPlayback

/// Video üstündeki denetim katmanı.
///
/// ⚠️ Katman **her zaman görünmez**: kullanıcı ekrana dokununca açılır,
/// birkaç saniye sonra kendiliğinden kapanır (bkz. `PlayerScreen`).
/// Görünürlük burada değil çağıran tarafta yönetiliyor — böylece
/// dokunma alanı tüm ekran olabiliyor, yalnızca düğmeler değil.
struct PlayerControlsOverlay: View {

    let title: String
    let subtitle: String?
    let isLive: Bool
    let state: PlaybackState
    let time: PlaybackTime
    let hasTracks: Bool
    let showsAirPlay: Bool
    let showsPictureInPicture: Bool
    let canZap: Bool
    let videoFit: VideoFit
    let rate: Float

    let onClose: () -> Void
    let onTogglePlay: () -> Void
    let onSkip: (TimeInterval) -> Void
    let onSeek: (TimeInterval) -> Void
    let onShowTracks: () -> Void
    let onToggleFit: () -> Void
    let onSetRate: (Float) -> Void
    let onPictureInPicture: () -> Void
    /// Canlı yayında kanal değiştirir: -1 önceki, +1 sonraki.
    let onZap: (Int) -> Void

    var body: some View {
        ZStack {
            // Düğmeler açık sahnelerde okunabilsin diye üst ve alt perdeler.
            LinearGradient(
                colors: [.black.opacity(0.7), .clear, .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                PlayerControlsTopBar(
                    title: title,
                    subtitle: subtitle,
                    isLive: isLive,
                    hasTracks: hasTracks,
                    showsAirPlay: showsAirPlay,
                    showsPictureInPicture: showsPictureInPicture,
                    videoFit: videoFit,
                    rate: rate,
                    onClose: onClose,
                    onShowTracks: onShowTracks,
                    onToggleFit: onToggleFit,
                    onSetRate: onSetRate,
                    onPictureInPicture: onPictureInPicture
                )
                Spacer(minLength: 0)
                PlayerTransportControls(
                    isLive: isLive,
                    state: state,
                    canZap: canZap,
                    onTogglePlay: onTogglePlay,
                    onSkip: onSkip,
                    onZap: onZap
                )
                Spacer(minLength: 0)
                bottomBar
            }
            .padding(Theme.Spacing.md)

        }
    }

    // MARK: - Alt

    @ViewBuilder
    private var bottomBar: some View {
        if isLive {
            HStack(spacing: Theme.Spacing.xs) {
                Circle()
                    .fill(Theme.Palette.live)
                    .frame(width: 8, height: 8)
                Text("CANLI")
                    .font(Theme.Typography.badge)
                    .kerning(1.5)
                    .foregroundColor(.white)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            PlayerScrubBar(time: time, onSeek: onSeek)
        }
    }
}
