import SwiftUI
import Foundation
import OctopusDesignSystem
import OctopusPlayback

/// Oynatıcı üst çubuğu. İkincil seçenekler tek iOS menüsünde toplanır;
/// küçük iPhone'larda başlık PiP/AirPlay düğmeleri arasında ezilmez.
struct PlayerControlsTopBar: View {

    @State private var showsOptions = false

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
            edgeControl(
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

            optionsControl
        }
        // PiP sistem düğmesi de koyu video üstünde beyaz kalmalı.
        .tint(.white)
    }

    private var optionsControl: some View {
        edgeVisual(glyph: .options)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .onTapGesture { showsOptions = true }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Oynatıcı seçenekleri")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { showsOptions = true }
            .confirmationDialog(
                "Oynatıcı seçenekleri",
                isPresented: $showsOptions,
                titleVisibility: .visible
            ) {
                Button(action: onToggleFit) {
                    Text(videoFit == .fill ? "Ekrana sığdır" : "Ekranı doldur")
                }

                if !isLive {
                    ForEach(rates, id: \.self) { option in
                        Button {
                            onSetRate(option)
                        } label: {
                            Text(rateOptionTitle(option))
                        }
                    }
                }

                if hasTracks {
                    Button(action: onShowTracks) {
                        Text("Ses ve altyazı")
                    }
                }

                Button("Vazgeç", role: .cancel) {}
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
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(controlBackground)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func edgeControl(
        glyph: PlayerEdgeGlyph,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        edgeVisual(glyph: glyph)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .onTapGesture(perform: action)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }

    private func edgeVisual(glyph: PlayerEdgeGlyph) -> some View {
        PlayerEdgeControlVisual(glyph: glyph)
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

    private func rateOptionTitle(_ value: Float) -> String {
        let title = rateTitle(value)
        return abs(value - rate) < 0.01 ? "\(title) · Seçili" : title
    }
}
