import SwiftUI
import Foundation
import OctopusDesignSystem
import OctopusPlayback

/// VLC video yüzeyinden ayrı bir UIWindow'da gösterilen kenar eylemleri.
struct PlayerEdgeControlsOverlay: View {
    @State private var showsOptions = false

    let isLive: Bool
    let hasTracks: Bool
    let videoFit: VideoFit
    let rate: Float
    let onClose: () -> Void
    let onShowTracks: () -> Void
    let onToggleFit: () -> Void
    let onSetRate: (Float) -> Void

    private let rates: [Float] = [0.5, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                PlayerEdgeControl(
                    glyph: .close,
                    label: "Oynatıcıyı kapat",
                    action: onClose
                )
                .frame(width: 44, height: 44)

                Spacer(minLength: 0)

                optionsControl
            }
            .padding(Theme.Spacing.md)

            Spacer(minLength: 0)
        }
    }

    private var optionsControl: some View {
        PlayerEdgeControl(
            glyph: .options,
            label: "Oynatıcı seçenekleri",
            action: { showsOptions = true }
        )
        .frame(width: 44, height: 44)
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

    private func rateTitle(_ value: Float) -> String {
        String(format: "%g×", value)
    }

    private func rateOptionTitle(_ value: Float) -> String {
        let title = rateTitle(value)
        return abs(value - rate) < 0.01 ? "\(title) · Seçili" : title
    }
}
