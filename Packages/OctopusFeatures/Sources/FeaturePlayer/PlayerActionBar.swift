import SwiftUI
import OctopusDesignSystem
import OctopusPlayback

/// Oynatıcının alt eylem çubuğu.
///
/// ⚠️ Bu çubuk bir `⋯` menüsünün yerine geçti. Ekran, hız ve ses/altyazı
/// seçenekleri önce o menünün içinde saklıydı: kullanıcı neyin nerede
/// olduğunu ancak menüyü açıp okuyarak öğrenebiliyordu. Üst çubukta ise
/// kapat, başlık, PiP, AirPlay ve menü yan yana sıkışıyordu.
///
/// Alanın yerleşik çözümü seçenekleri **etiketli** olarak alta almak:
/// düğme aranmaz, okunur. Kilit de sol kenarda havada durmak yerine
/// buraya taşındı — diğer seçeneklerle aynı türden bir eylem.
struct PlayerActionBar: View {

    let isLive: Bool
    let isChannel: Bool
    let canZap: Bool
    /// Ses düğmesi yalnızca **seçenek varsa** çıkar: tek izli bir
    /// yayında düğme açmak, seçim sunmadan kullanıcıya iş çıkarır.
    let hasAudioChoice: Bool
    let hasSubtitleChoice: Bool
    let videoFit: VideoFit
    let rate: Float

    let onToggleFit: () -> Void
    let onSetRate: (Float) -> Void
    let onShowTracks: (PlayerTrackPicker.Focus) -> Void
    let onShowLivePanel: () -> Void
    let onLock: () -> Void
    let onZap: (Int) -> Void

    @State private var showsRates = false
    @Environment(\.locale) private var locale

    private let rates: [Float] = [0.5, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        // ⚠️ Etiketler her ekrana sığmaz: dikey iPhone'da beş etiketli düğme
        // 390 puntoya girmiyor ve yazılar kırpılıyordu. `ViewThatFits` yer
        // varsa etiketli, yoksa simge sürümü seçer — kırpma yerine derece
        // derece sadeleşme.
        ViewThatFits(in: .horizontal) {
            row(showsTitles: true)
            row(showsTitles: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(showsTitles: Bool) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            button(
                title: "Kilit",
                systemImage: "lock.open",
                accessibilityLabel: "Oynatıcıyı kilitle",
                showsTitle: showsTitles,
                action: onLock
            )

            // ⚠️ Etiketler kasten kısa. Uzun hâlleri ("Ekranı doldur",
            // "Ses ve altyazı") dikey iPhone'a sığmıyor ve çubuk tümüyle
            // simgeye düşüyordu — kullanıcının okuyamadığı hâl. Anlamın
            // tamamı erişilebilirlik etiketinde duruyor.
            button(
                title: videoFit == .fill ? "Sığdır" : "Doldur",
                systemImage: videoFit == .fill
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right",
                accessibilityLabel: videoFit == .fill ? "Ekrana sığdır" : "Ekranı doldur",
                showsTitle: showsTitles,
                action: onToggleFit
            )

            // ⚠️ Hız yalnızca kayıtlı içerikte: canlı yayında hızlandırmak
            // tamponu tüketip yayını kopartır.
            if !isLive {
                rateButton(showsTitle: showsTitles)
            }

            // ⚠️ Ayrı düğmeler: birleşik listede altyazı arayan kullanıcı
            // önce ses bölümünden geçmek zorundaydı. İkisi farklı ihtiyaç,
            // özellikle film ve dizide.
            if hasAudioChoice {
                button(
                    title: "Ses",
                    systemImage: "waveform",
                    accessibilityLabel: "Ses izi",
                    showsTitle: showsTitles,
                    action: { onShowTracks(.audio) }
                )
            }

            if hasSubtitleChoice {
                button(
                    title: "Altyazı",
                    systemImage: "captions.bubble",
                    accessibilityLabel: "Altyazı",
                    showsTitle: showsTitles,
                    action: { onShowTracks(.subtitle) }
                )
            }

            if isChannel {
                if !isLive, canZap {
                    button(title: "Önceki kanal", systemImage: "backward.end.fill", accessibilityLabel: "Önceki kanal",
                           showsTitle: false, action: { onZap(-1) })
                        .accessibilityIdentifier("player.channels.previous")
                    button(title: "Sonraki kanal", systemImage: "forward.end.fill", accessibilityLabel: "Sonraki kanal",
                           showsTitle: false, action: { onZap(1) })
                        .accessibilityIdentifier("player.channels.next")
                }
                button(
                    title: "Kanallar",
                    systemImage: "list.bullet.rectangle",
                    accessibilityLabel: "Kanallar",
                    showsTitle: showsTitles,
                    action: onShowLivePanel
                )
                .accessibilityIdentifier("player.channels.open")
            }
        }
    }

    // MARK: - Hız

    /// Hız düğmesi seçili değeri **üstünde taşır**: kullanıcı 1,5×'te
    /// kaldığını menüyü açmadan görür. Yanlışlıkla hızlı kalmış bir
    /// oynatma, sebebi görünmediğinde "uygulama bozuk" gibi hissettiriyor.
    private func rateButton(showsTitle: Bool) -> some View {
        button(
            title: abs(rate - 1) < 0.01 ? "Hız" : rateTitle(rate),
            systemImage: "speedometer",
            accessibilityLabel: "Oynatma hızı",
            showsTitle: showsTitle,
            isHighlighted: abs(rate - 1) >= 0.01,
            action: { showsRates = true }
        )
        .confirmationDialog(
            "Oynatma hızı",
            isPresented: $showsRates,
            titleVisibility: .visible
        ) {
            ForEach(rates, id: \.self) { option in
                Button {
                    onSetRate(option)
                } label: {
                    Text(AppLocalization.localized(rateOptionTitle(option), locale: locale))
                }
            }
            Button("Vazgeç", role: .cancel) {}
        }
        .modifier(PlayerControlsPressTracker(isPressed: showsRates))
    }

    private func rateTitle(_ value: Float) -> String {
        String(format: "%g×", value)
    }

    private func rateOptionTitle(_ value: Float) -> String {
        let title = rateTitle(value)
        return abs(value - rate) < 0.01 ? "\(title) · Seçili" : title
    }

    // MARK: - Düğme

    private func button(
        title: String,
        systemImage: String,
        accessibilityLabel: String,
        showsTitle: Bool,
        isHighlighted: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                if showsTitle {
                    Text(AppLocalization.localized(title, locale: locale))
                        .font(Theme.Typography.caption)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(isHighlighted ? Theme.Palette.accent : .white)
            // ⚠️ Yükseklik 44: Apple'ın dokunma hedefi alt sınırı. Video
            // üstünde ıskalanan düğme, yanlışlıkla oynat/duraklat demektir.
            .frame(height: 44)
            .padding(.horizontal, showsTitle ? Theme.Spacing.md : Theme.Spacing.sm)
            .frame(minWidth: 44)
            .background(.black.opacity(0.42), in: Capsule())
            .overlay {
                Capsule().stroke(.white.opacity(0.14), lineWidth: 0.5)
            }
        }
        .buttonStyle(PlayerControlsPlainButtonStyle())
        .accessibilityLabel(AppLocalization.localized(accessibilityLabel, locale: locale))
    }
}
