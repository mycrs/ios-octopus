import SwiftUI
import OctopusDesignSystem

/// Belirsiz bağlantı, yüzdeli aktarım ve başarı durumlarını tek yüzeyde taşır.
struct SyncProgressIndicator: View {
    let fraction: Double?
    let isFinished: Bool
    let isPulsing: Bool
    let reduceMotion: Bool

    @Environment(\.brandColor) private var brandColor

    var body: some View {
        ZStack {
            Circle()
                .fill(brandColor.opacity(0.10))
                .frame(width: 104, height: 104)
                .scaleEffect(isPulsing && !reduceMotion ? 1.10 : 0.96)
                .opacity(isPulsing && !reduceMotion ? 0.42 : 1)
                .animation(pulseAnimation, value: isPulsing)

            Circle()
                .stroke(Theme.Palette.separator, lineWidth: 6)
                .frame(width: 82, height: 82)

            indicatorContent
        }
    }

    @ViewBuilder
    private var indicatorContent: some View {
        if isFinished {
            Circle()
                .fill(brandColor)
                .frame(width: 82, height: 82)

            Image(systemName: "checkmark")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)
                .transition(.scale.combined(with: .opacity))
        } else if let fraction {
            Circle()
                .trim(from: 0, to: max(fraction, 0.04))
                .stroke(
                    brandColor,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 82, height: 82)
                .animation(.easeInOut(duration: 0.35), value: fraction)

            Text("\(Int(fraction * 100))%")
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundColor(Theme.Palette.textPrimary)
                .monospacedDigit()
        } else {
            ProgressView()
                .tint(brandColor)
                .scaleEffect(1.15)
        }
    }

    private var pulseAnimation: Animation? {
        reduceMotion
            ? nil
            : .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
    }
}
