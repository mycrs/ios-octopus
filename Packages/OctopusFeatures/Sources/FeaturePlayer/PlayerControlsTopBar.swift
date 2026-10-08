import SwiftUI
import Foundation
import OctopusDesignSystem
import OctopusPlayback

/// Oynatıcı üst çubuğu: kapat, başlık ve **sistem** düğmeleri.
///
/// ⚠️ Burada yalnızca içeriği başka bir yere gönderen düğmeler kalır
/// (PiP, AirPlay). Oynatmayı biçimlendiren seçenekler — ekran, hız,
/// ses/altyazı — alttaki `PlayerActionBar`'da. Önce hepsi buradaydı ve
/// üst çubuk beş denetimle sıkışıyordu; başlık ezilen ilk şey oluyordu.
struct PlayerControlsTopBar: View {

    let title: String
    let subtitle: String?
    let showsAirPlay: Bool
    let showsPictureInPicture: Bool

    let onClose: () -> Void
    let onPictureInPicture: () -> Void

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
                .accessibilityIdentifier("player.close")

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

            }
            .frame(width: geometry.size.width, height: 44, alignment: .leading)
        }
        .frame(height: 44)
        // PiP sistem düğmesi de koyu video üstünde beyaz kalmalı.
        .tint(.white)
    }

    private func titleWidth(in totalWidth: CGFloat) -> CGFloat {
        // Kapat düğmesi + varsa PiP + varsa AirPlay.
        let fixedControlCount = 1
            + (showsPictureInPicture ? 1 : 0)
            + (showsAirPlay ? 1 : 0)
        let controlsWidth = CGFloat(fixedControlCount) * 44
        // Başlık da bir HStack öğesi olduğundan boşluk sayısı denetim sayısıdır.
        let spacingWidth = CGFloat(fixedControlCount) * Theme.Spacing.sm
        return max(totalWidth - controlsWidth - spacingWidth, 0)
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
}
