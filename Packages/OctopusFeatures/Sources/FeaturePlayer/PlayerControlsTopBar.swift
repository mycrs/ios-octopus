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
    @Environment(\.locale) private var locale

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                PlayerEdgeControl(
                    glyph: .close,
                    label: "Oynatıcıyı kapat",
                    action: onClose
                )
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.Typography.sectionTitle)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Theme.Typography.caption)
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                // Ekranın gerçek genişliğinden sabit denetimleri çıkar. SwiftUI'ın
                // ideal genişliği başlığı büyütüp kenarları kırpamasın.
                .frame(width: titleWidth(in: geometry.size.width), alignment: .leading)

                if showsPictureInPicture {
                    iconButton(
                        systemName: "pip.enter",
                        label: "Resim içinde resim",
                        action: onPictureInPicture
                    )
                }

                if showsAirPlay {
                    AirPlayButton()
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay {
                            Circle().stroke(.white.opacity(0.14), lineWidth: 0.5)
                        }
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("AirPlay")
                }

                optionsControl
            }
            .frame(width: geometry.size.width, height: 44, alignment: .leading)
        }
        .frame(height: 44)
        // PiP sistem düğmesi de koyu video üstünde beyaz kalmalı.
        .tint(.white)
    }

    private func titleWidth(in totalWidth: CGFloat) -> CGFloat {
        let fixedControlCount = 2
            + (showsPictureInPicture ? 1 : 0)
            + (showsAirPlay ? 1 : 0)
        let controlsWidth = CGFloat(fixedControlCount) * 44
        // Başlık da bir HStack öğesi olduğundan boşluk sayısı denetim sayısıdır.
        let spacingWidth = CGFloat(fixedControlCount) * Theme.Spacing.sm
        return max(totalWidth - controlsWidth - spacingWidth, 0)
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
                Text(
                    AppLocalization.localized(
                        videoFit == .fill ? "Ekrana sığdır" : "Ekranı doldur",
                        locale: locale
                    )
                )
            }

            if !isLive {
                ForEach(rates, id: \.self) { option in
                    Button {
                        onSetRate(option)
                    } label: {
                        Text(AppLocalization.localized(rateOptionTitle(option), locale: locale))
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
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle().stroke(.white.opacity(0.14), lineWidth: 0.5)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.localized(label, locale: locale))
    }

    private func rateTitle(_ value: Float) -> String {
        String(format: "%g×", value)
    }

    private func rateOptionTitle(_ value: Float) -> String {
        let title = rateTitle(value)
        return abs(value - rate) < 0.01 ? "\(title) · Seçili" : title
    }

}
