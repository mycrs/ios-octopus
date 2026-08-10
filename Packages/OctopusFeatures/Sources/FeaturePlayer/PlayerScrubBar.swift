import SwiftUI
import OctopusDesignSystem
import OctopusPlayback

/// Sürüklenebilir ilerleme çubuğu.
///
/// ## Neden `Slider` değil?
/// İki şey gerekiyordu ve `Slider` ikisini de vermiyor: **tampon
/// göstergesi** (indirilmiş ama henüz oynatılmamış kısım — IPTV'de
/// takılmanın habercisi) ve sürükleme boyunca konumu yayınlamadan
/// önizleme. `Slider`'ın değeri bağlanır bağlanmaz her piksel hareketi
/// bir arama isteği tetiklerdi.
struct PlayerScrubBar: View {

    let time: PlaybackTime
    /// Kullanıcı parmağını kaldırdığında çağrılır — sürükleme boyunca değil.
    let onSeek: (TimeInterval) -> Void

    @State private var draggingFraction: Double?
    @Environment(\.brandColor) private var brandColor

    private let trackHeight: CGFloat = 4
    private let knobSize: CGFloat = 14

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            track
            labels
        }
    }

    private var displayedFraction: Double {
        draggingFraction ?? time.fraction
    }

    private var track: some View {
        GeometryReader { geometry in
            let width = geometry.size.width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.25))
                    .frame(height: trackHeight)

                // Tampon: nereye kadar indirildi.
                Capsule()
                    .fill(Color.white.opacity(0.4))
                    .frame(width: width * bufferedFraction, height: trackHeight)

                Capsule()
                    .fill(brandColor)
                    .frame(width: width * displayedFraction, height: trackHeight)

                Circle()
                    .fill(Color.white)
                    .frame(width: knobSize, height: knobSize)
                    // Tutamak kenarlarda taşmasın diye yarıçapı kadar içeri alınır.
                    .offset(x: (width - knobSize) * displayedFraction)
            }
            .frame(height: knobSize)
            .contentShape(Rectangle())
            .gesture(dragGesture(width: width))
        }
        .frame(height: knobSize)
    }

    private var bufferedFraction: Double {
        guard let duration = time.duration, duration > 0 else { return 0 }
        return min(max(time.bufferedUpTo / duration, 0), 1)
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard width > 0 else { return }
                draggingFraction = min(max(value.location.x / width, 0), 1)
            }
            .onEnded { _ in
                defer { draggingFraction = nil }
                guard
                    let fraction = draggingFraction,
                    let duration = time.duration, duration > 0
                else { return }

                onSeek(fraction * duration)
            }
    }

    private var labels: some View {
        HStack {
            Text(PlayerViewModel.timeLabel(currentLabelSeconds))
            Spacer()
            // Kalan süre: film izlerken "ne kadar kaldı" sorusunun cevabı
            // geçen süreden daha kullanışlı.
            Text(remainingLabel)
        }
        .font(Theme.Typography.caption.monospacedDigit())
        .foregroundColor(.white.opacity(0.8))
    }

    private var currentLabelSeconds: TimeInterval? {
        guard let duration = time.duration else { return time.current }
        return displayedFraction * duration
    }

    private var remainingLabel: String {
        guard
            let duration = time.duration,
            let current = currentLabelSeconds
        else { return "--:--" }

        return "-" + PlayerViewModel.timeLabel(max(duration - current, 0))
    }
}
