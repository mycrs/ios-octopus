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
    let isChannel: Bool
    let state: PlaybackState
    let time: PlaybackTime
    let hasAudioChoice: Bool
    let hasSubtitleChoice: Bool
    let showsAirPlay: Bool
    let showsPictureInPicture: Bool
    let canZap: Bool
    let videoFit: VideoFit
    let rate: Float

    let onClose: () -> Void
    let onTogglePlay: () -> Void
    let onSkip: (TimeInterval) -> Void
    let onSeek: (TimeInterval) -> Void
    let onShowTracks: (PlayerTrackPicker.Focus) -> Void
    let onToggleFit: () -> Void
    let onSetRate: (Float) -> Void
    let onPictureInPicture: () -> Void
    let onLock: () -> Void
    let onShowLivePanel: () -> Void
    /// Canlı yayında kanal değiştirir: -1 önceki, +1 sonraki.
    let onZap: (Int) -> Void

    var body: some View {
        // Kontrast yalnızca denetimlerin arkasında; video üzerinde perde veya blur yok.
        VStack(spacing: 0) {
            PlayerControlsTopBar(
                title: title,
                subtitle: subtitle,
                showsAirPlay: showsAirPlay,
                showsPictureInPicture: showsPictureInPicture,
                onClose: onClose,
                onPictureInPicture: onPictureInPicture
            )
            .padding(Theme.Spacing.xs)
            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            Spacer(minLength: 0)
            PlayerTransportControls(
                isLive: isLive,
                state: state,
                canZap: canZap,
                onTogglePlay: onTogglePlay,
                onSkip: onSkip,
                onZap: onZap
            )
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(.black.opacity(0.45), in: Capsule())
            Spacer(minLength: 0)
            bottomBar
                .padding(Theme.Spacing.sm)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(Theme.Spacing.md)
    }

    // MARK: - Alt

    /// Alt bölge iki katmandır: üstte **içeriğin nerede olduğu** (canlı
    /// rozeti ya da konum çubuğu), altta **ne yapılabileceği**.
    ///
    /// ⚠️ Ayrım bilinçli: ikisi tek satıra karıştığında konum çubuğu
    /// düğmelerle yarışıyor ve dar ekranda sürükleme alanı kalmıyordu.
    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if isLive {
                liveBadge
            } else {
                PlayerScrubBar(time: time, onSeek: onSeek)
            }

            PlayerActionBar(
                isLive: isLive,
                isChannel: isChannel,
                canZap: canZap,
                hasAudioChoice: hasAudioChoice,
                hasSubtitleChoice: hasSubtitleChoice,
                videoFit: videoFit,
                rate: rate,
                onToggleFit: onToggleFit,
                onSetRate: onSetRate,
                onShowTracks: onShowTracks,
                onShowLivePanel: onShowLivePanel,
                onLock: onLock,
                onZap: onZap
            )
        }
    }

    private var liveBadge: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Circle()
                .fill(Theme.Palette.live)
                .frame(width: 8, height: 8)
            Text("CANLI")
                .font(Theme.Typography.badge)
                .kerning(1.5)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
