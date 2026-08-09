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
    let canZap: Bool
    let videoFit: VideoFit

    let onClose: () -> Void
    let onTogglePlay: () -> Void
    let onSkip: (TimeInterval) -> Void
    let onSeek: (TimeInterval) -> Void
    let onShowTracks: () -> Void
    let onToggleFit: () -> Void
    /// Canlı yayında kanal değiştirir: -1 önceki, +1 sonraki.
    let onZap: (Int) -> Void

    /// İleri/geri sarma adımı. 10 sn sektör standardı; reklam atlamaya
    /// yetecek kadar büyük, sahne kaçırmayacak kadar küçük.
    private let skipStep: TimeInterval = 10

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
                topBar
                Spacer(minLength: 0)
                transportRow
                Spacer(minLength: 0)
                bottomBar
            }
            .padding(Theme.Spacing.md)
        }
    }

    // MARK: - Üst

    private var topBar: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Button(action: onClose) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.black.opacity(0.35)))
            }
            .accessibilityLabel("Oynatıcıyı kapat")

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.sectionTitle)
                    .foregroundColor(.white)
                    .lineLimit(1)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if showsAirPlay {
                AirPlayButton()
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.black.opacity(0.35)))
                    .accessibilityLabel("AirPlay")
            }

            // ⚠️ IPTV'de gerçek bir ihtiyaç: pek çok kanal 4:3 yayın yapar
            // ya da yayına kendi siyah bantlarını gömer.
            iconButton(
                systemName: videoFit == .fill
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right",
                label: videoFit == .fill ? "Ekrana sığdır" : "Ekranı doldur",
                action: onToggleFit
            )

            if hasTracks {
                iconButton(
                    systemName: "captions.bubble",
                    label: "Ses ve altyazı",
                    action: onShowTracks
                )
            }
        }
    }

    private func iconButton(
        systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(.black.opacity(0.35)))
        }
        .accessibilityLabel(label)
    }

    // MARK: - Orta

    /// Yan düğmeler içeriğe göre değişir.
    ///
    /// ⚠️ Canlı yayında sarma **yok** — konum kavramı olmadığı için
    /// düğmeler hiçbir şey yapmazdı. Boşalan yer kanal değiştirmeye
    /// veriliyor: IPTV'de en sık yapılan iş bu ve eskiden oynatıcıdan
    /// çıkıp listeye dönmek gerekiyordu.
    private var transportRow: some View {
        HStack(spacing: Theme.Spacing.xl) {
            if isLive {
                if canZap {
                    transportButton(icon: "backward.end.fill", label: "Önceki kanal") { onZap(-1) }
                }
            } else {
                transportButton(icon: "gobackward.10", label: "10 saniye geri") {
                    onSkip(-skipStep)
                }
            }

            playPauseButton

            if isLive {
                if canZap {
                    transportButton(icon: "forward.end.fill", label: "Sonraki kanal") { onZap(1) }
                }
            } else {
                transportButton(icon: "goforward.10", label: "10 saniye ileri") {
                    onSkip(skipStep)
                }
            }
        }
    }

    private var playPauseButton: some View {
        Button(action: onTogglePlay) {
            ZStack {
                Circle()
                    .fill(.black.opacity(0.4))
                    .frame(width: 68, height: 68)

                if state.showsSpinner {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Image(systemName: state == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                }
            }
        }
        .disabled(state.showsSpinner)
        .accessibilityLabel(state == .playing ? "Duraklat" : "Oynat")
    }

    private func transportButton(
        icon: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundColor(.white)
                .frame(width: 52, height: 52)
        }
        .accessibilityLabel(label)
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
