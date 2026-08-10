import SwiftUI
import Foundation
import OctopusDesignSystem
import OctopusPlayback

/// Oynatıcı üst çubuğu. İkincil seçenekler tek iOS menüsünde toplanır;
/// küçük iPhone'larda başlık PiP/AirPlay düğmeleri arasında ezilmez.
struct PlayerControlsTopBar: View {

    let title: String
    let subtitle: String?
    let isLive: Bool
    let hasTracks: Bool
    let showsAirPlay: Bool
    let showsPictureInPicture: Bool
    let videoFit: VideoFit
    let rate: Float

    let onClose: () -> Void
    let onShowTracks: () -> Void
    let onToggleFit: () -> Void
    let onSetRate: (Float) -> Void
    let onPictureInPicture: () -> Void

    private let rates: [Float] = [0.5, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            edgeButton(
                glyph: .close,
                label: "Oynatıcıyı kapat",
                action: onClose
            )

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

            if showsPictureInPicture {
                iconButton(
                    systemName: "pip.enter",
                    label: "Resim içinde resim",
                    action: onPictureInPicture
                )
            }

            if showsAirPlay {
                AirPlayButton()
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.black.opacity(0.35)))
                    .accessibilityLabel("AirPlay")
            }

            optionsMenu
        }
        // `UIHostingController` içinde sistem Button/Menu tonu içerik
        // güncellenirken siyaha dönebiliyor. Kenar eylemleri video üstünde
        // her koşulda beyaz ve okunur kalmalı.
        .tint(.white)
    }

    private var optionsMenu: some View {
        Menu {
            Button(action: onToggleFit) {
                Label(
                    videoFit == .fill ? "Ekrana sığdır" : "Ekranı doldur",
                    systemImage: videoFit == .fill
                        ? "arrow.down.right.and.arrow.up.left"
                        : "arrow.up.left.and.arrow.down.right"
                )
            }

            if !isLive {
                Menu {
                    ForEach(rates, id: \.self) { option in
                        Button {
                            onSetRate(option)
                        } label: {
                            if abs(option - rate) < 0.01 {
                                Label(rateTitle(option), systemImage: "checkmark")
                            } else {
                                Text(rateTitle(option))
                            }
                        }
                    }
                } label: {
                    Label("Oynatma hızı · \(rateTitle(rate))", systemImage: "speedometer")
                }
            }

            if hasTracks {
                Button(action: onShowTracks) {
                    Label("Ses ve altyazı", systemImage: "captions.bubble")
                }
            }
        } label: {
            edgeVisual(glyph: .options)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Oynatıcı seçenekleri")
        .frame(width: 44, height: 44)
    }

    private func iconButton(
        systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(controlBackground)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func edgeButton(
        glyph: PlayerEdgeGlyph,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            edgeVisual(glyph: glyph)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .frame(width: 44, height: 44)
    }

    @ViewBuilder
    private func edgeVisual(glyph: PlayerEdgeGlyph) -> some View {
        ZStack {
            controlBackground

            switch glyph {
            case .close:
                PlayerCloseGlyph()
                    .stroke(
                        .white,
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                    )
            case .options:
                PlayerOptionsGlyph()
                    .fill(.white)
            }
        }
        .allowsHitTesting(false)
    }

    private var controlBackground: some View {
        Circle()
            .fill(.black.opacity(0.58))
            .overlay {
                Circle().stroke(.white.opacity(0.14), lineWidth: 0.5)
            }
    }

    private func rateTitle(_ value: Float) -> String {
        String(format: "%g×", value)
    }
}
