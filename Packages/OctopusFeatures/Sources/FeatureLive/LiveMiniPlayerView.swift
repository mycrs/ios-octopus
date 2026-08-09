import SwiftUI
import OctopusDomain
import OctopusDesignSystem
import OctopusPlayback

/// Canlı TV'nin tepesindeki **gömülü oynatıcı**.
///
/// ## Referanstaki davranış
/// Listeden bir kanala dokunulunca tam ekrana atlamaz; yayın burada,
/// listenin üstünde başlar. Kullanıcı aşağıda gezinmeye devam ederken
/// izlemeyi sürdürür. Tam ekran isteyen bu alana dokunur.
///
/// ⚠️ Bu görünüm `FeaturePlayer`'ı **görmez**. Video yüzeyi ve denetleyici
/// `OctopusPlayback`'ten geliyor; iki ekran arasında bağ yok
/// (bkz. CLAUDE.md demir kural 3).
struct LiveMiniPlayerView: View {

    let channel: Channel?
    let program: EPGProgram?
    let controller: PlayerController
    /// Hiçbir kanal seçilmemişken gösterilecek afiş — ilk açılışta
    /// ekranın tepesi boş kalmasın.
    let placeholderChannel: Channel?
    let onExpand: () -> Void

    /// Video oranı — yayınların neredeyse tamamı 16:9.
    ///
    /// ⚠️ Sabit yükseklik (eski hâli: 220pt) iki sebeple yanlıştı:
    /// cihaz genişliğine göre ölçeklenmiyordu (geniş telefonlarda videonun
    /// altında/üstünde siyah bant kalıyordu) ve kart durum çubuğunun altına
    /// uzandığı için 220pt'nin ~60pt'si görünmüyordu — geriye çok dar bir
    /// şerit kalıyordu. Oranla hesaplanınca video kutuyu **tam** dolduruyor.
    private let aspectRatio: CGFloat = 16.0 / 9.0

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            surface
            scrim
            info
            if controller.state.showsSpinner { spinner }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture(perform: onExpand)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(channel.map { "Oynatılıyor: \($0.name)" } ?? "Oynatıcı")
        .accessibilityHint("Tam ekran açar")
        // Sabit yükseklik erişilebilirlik yazı boyutunda taşmasın.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    // MARK: - Video

    @ViewBuilder
    private var surface: some View {
        if channel != nil {
            // ⚠️ `.id`: her yeni motorda yüzey baştan kurulmalı, yoksa
            // ekranda bırakılmış eski motorun katmanı kalır
            // (bkz. `PlayerController.surfaceGeneration`).
            VideoSurfaceView(makeSurface: controller.makeVideoView)
                .id(controller.surfaceGeneration)
                .background(Color.black)
        } else {
            placeholderBackdrop
        }
    }

    /// Henüz bir şey oynatılmıyor: son izlenen kanalın logosu.
    private var placeholderBackdrop: some View {
        RemoteImageView(
            url: placeholderChannel?.logoURL,
            contentMode: .fit,
            targetWidth: 320
        ) {
            ZStack {
                Theme.Palette.surfaceElevated
                Image(systemName: "tv")
                    .font(.system(size: 40))
                    .foregroundColor(Theme.Palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Theme.Palette.surface)
        .clipped()
    }

    private var spinner: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .tint(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Üst katman

    /// Alttaki yazılar açık sahnelerde de okunsun diye perde.
    ///
    /// ⚠️ Üstteki ikinci perde kaldırıldı: kart artık durum çubuğunun
    /// altına uzanmıyor, saat ve pil ikonlarını karartmaya gerek yok.
    /// Videonun üst yarısını gereksizce koyultuyordu.
    private var scrim: some View {
        LinearGradient(
            colors: [.clear, .black.opacity(0.75)],
            startPoint: .center,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }

    private var info: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.xs) {
                    Circle()
                        .fill(Theme.Palette.live)
                        .frame(width: 6, height: 6)
                    Text(channel == nil ? "KALDIĞIN KANAL" : "CANLI")
                        .font(Theme.Typography.badge)
                        .kerning(1.5)
                        .foregroundColor(.white.opacity(0.85))
                }

                if let name = (channel ?? placeholderChannel)?.name {
                    Text(name)
                        .font(Theme.Typography.sectionTitle)
                        .foregroundColor(.white)
                        .lineLimit(1)
                }

                if let program {
                    Text(program.title)
                        .font(Theme.Typography.caption)
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            // Tam ekran ipucu: dokunma alanı zaten tüm kart, bu yalnızca
            // "buradan büyütebilirsin" işareti.
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(.black.opacity(0.4)))
                .accessibilityHidden(true)
        }
        // Sol kenar liste satırlarıyla aynı hizada kalsın.
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.md)
    }
}
