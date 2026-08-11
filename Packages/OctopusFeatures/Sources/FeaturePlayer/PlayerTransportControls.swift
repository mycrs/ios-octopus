import SwiftUI
import OctopusDesignSystem
import OctopusPlayback

/// Canlıda kanal değiştirme, VOD'da on saniyelik sarma denetimleri.
struct PlayerTransportControls: View {

    let isLive: Bool
    let state: PlaybackState
    let canZap: Bool
    let onTogglePlay: () -> Void
    let onSkip: (TimeInterval) -> Void
    let onZap: (Int) -> Void

    private let skipStep: TimeInterval = 10
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: Theme.Spacing.xl) {
            if isLive {
                if canZap {
                    transportButton(icon: "backward.end.fill", label: "Önceki kanal") {
                        onZap(-1)
                    }
                }
            } else {
                transportButton(icon: "gobackward.10", label: "10 saniye geri") {
                    onSkip(-skipStep)
                }
            }

            playPauseButton

            if isLive {
                if canZap {
                    transportButton(icon: "forward.end.fill", label: "Sonraki kanal") {
                        onZap(1)
                    }
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
        .accessibilityLabel(
            AppLocalization.localized(
                state == .playing ? "Duraklat" : "Oynat",
                locale: locale
            )
        )
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
        .accessibilityLabel(AppLocalization.localized(label, locale: locale))
    }
}
