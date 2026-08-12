import SwiftUI
import OctopusDesignSystem

/// Belirsiz bağlantı, yüzdeli aktarım ve başarı durumlarını tek yüzeyde taşır.
struct SyncProgressIndicator: View {
    let fraction: Double?
    let isFinished: Bool
    let isPulsing: Bool
    let reduceMotion: Bool
    let logoURL: URL?

    @Environment(\.brandColor) private var brandColor

    var body: some View {
        ZStack {
            Circle()
                .fill(brandColor.opacity(0.10))
                .frame(width: 122, height: 122)
                .scaleEffect(isPulsing && !reduceMotion ? 1.10 : 0.96)
                .opacity(isPulsing && !reduceMotion ? 0.42 : 1)
                .animation(pulseAnimation, value: isPulsing)

            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 5)
                .frame(width: 104, height: 104)

            progressRing

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.Palette.background.opacity(0.92))
                .frame(width: 78, height: 78)
                .overlay {
                    OnboardingBrandLogo(logoURL: logoURL, size: 62)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                }
                .shadow(color: brandColor.opacity(0.22), radius: 18, y: 8)

            statusBadge
        }
        .frame(width: 126, height: 126)
    }

    @ViewBuilder
    private var progressRing: some View {
        if isFinished {
            Circle()
                .stroke(Theme.Palette.success, lineWidth: 5)
                .frame(width: 104, height: 104)
        } else if let fraction {
            Circle()
                .trim(from: 0, to: max(fraction, 0.04))
                .stroke(
                    AngularGradient(
                        colors: [brandColor.opacity(0.28), brandColor, .white, brandColor],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 104, height: 104)
                .animation(.easeInOut(duration: 0.35), value: fraction)
        } else {
            Circle()
                .trim(from: 0.05, to: 0.34)
                .stroke(
                    AngularGradient(
                        colors: [brandColor.opacity(0.16), brandColor, .white],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .frame(width: 104, height: 104)
                .rotationEffect(.degrees(isPulsing && !reduceMotion ? 360 : 0))
                .animation(spinAnimation, value: isPulsing)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if isFinished {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(Theme.Palette.success)
                .clipShape(Circle())
                .overlay { Circle().stroke(Theme.Palette.background, lineWidth: 3) }
                .offset(x: 40, y: 40)
                .transition(.scale.combined(with: .opacity))
        } else if let fraction {
            Text("\(Int(fraction * 100))%")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Palette.textPrimary)
                .monospacedDigit()
                .padding(.horizontal, 8)
                .frame(height: 25)
                .background(Theme.Palette.surfaceElevated)
                .clipShape(Capsule())
                .overlay { Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1) }
                .offset(y: 53)
        }
    }

    private var pulseAnimation: Animation? {
        reduceMotion
            ? nil
            : .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
    }

    private var spinAnimation: Animation? {
        reduceMotion
            ? nil
            : .linear(duration: 1.35).repeatForever(autoreverses: false)
    }
}
