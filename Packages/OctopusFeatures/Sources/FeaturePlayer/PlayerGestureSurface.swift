import SwiftUI
import UIKit

struct PlayerGestureSurface: View {
    let isEnabled: Bool
    let isLive: Bool
    let volume: Float
    let onSingleTap: () -> Void
    let onSkip: (TimeInterval) -> Void
    let onVolume: (Float) -> Void
    let onBrightness: (CGFloat) -> Void

    @State private var verticalStart: CGFloat?
    @State private var adjustsBrightness = false

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                tapZone(delta: -10)
                tapZone(delta: 10)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onSingleTap)
            .gesture(verticalGesture(in: geometry.size))
        }
        .allowsHitTesting(isEnabled)
    }

    private func tapZone(delta: TimeInterval) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                guard !isLive else { return }
                onSkip(delta)
            }
    }

    private func verticalGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                guard abs(value.translation.height) > abs(value.translation.width) else { return }

                if verticalStart == nil {
                    adjustsBrightness = value.startLocation.x < size.width / 2
                    verticalStart = adjustsBrightness
                        ? UIScreen.main.brightness
                        : CGFloat(volume)
                }

                guard let verticalStart else { return }
                let height = max(size.height, 1)
                let adjusted = min(max(verticalStart - value.translation.height / height, 0), 1)

                if adjustsBrightness {
                    UIScreen.main.brightness = adjusted
                    onBrightness(adjusted)
                } else {
                    onVolume(Float(adjusted))
                }
            }
            .onEnded { _ in verticalStart = nil }
    }
}

struct PlayerGestureNotice: Equatable {
    let icon: String
    let text: String
}

struct PlayerGestureNoticeView: View {
    let notice: PlayerGestureNotice

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: notice.icon)
                .font(.system(size: 25, weight: .semibold))
            Text(notice.text)
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
        .allowsHitTesting(false)
    }
}
