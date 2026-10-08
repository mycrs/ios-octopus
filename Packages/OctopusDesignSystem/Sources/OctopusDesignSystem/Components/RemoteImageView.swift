import SwiftUI
import Nuke
import NukeUI

/// Önbellekli uzak görsel.
///
/// IPTV listelerinde binlerce logo/afiş var ve kullanıcı hızla kaydırıyor.
/// `AsyncImage` her görünüşte yeniden indirdiği için hem ağ hem de pil
/// tüketiyor; `LazyImage` bellek ve disk önbelleği kullanır.
///
/// Adres yoksa veya yükleme başarısızsa yer tutucu gösterilir — logo
/// eksikliği satırın boş görünmesine yol açmamalı.
public struct RemoteImageView<Placeholder: View>: View {

    @Environment(\.displayScale) private var displayScale

    private let url: URL?
    private let contentMode: SwiftUI.ContentMode
    private let targetWidth: CGFloat?
    private let placeholder: () -> Placeholder

    /// - Parameter targetWidth: Görselin ekranda kaplayacağı **nokta**
    ///   genişliği. Verilirse indirilen görsel bu boyuta küçültülerek
    ///   çözülür (aşağıdaki nota bak). Bilinmiyorsa `nil` bırakılabilir.
    public init(
        url: URL?,
        contentMode: SwiftUI.ContentMode = .fit,
        targetWidth: CGFloat? = nil,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.contentMode = contentMode
        self.targetWidth = targetWidth
        self.placeholder = placeholder
    }

    public var body: some View {
        if let url {
            LazyImage(request: request(for: url)) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: contentMode)
                } else {
                    placeholder()
                }
            }
        } else {
            placeholder()
        }
    }

    /// Nuke'nin thumbnail decoder'ı, tam bitmap oluşmadan boyutu sınırlar.
    /// Resize tek başına çözülmüş görseli küçültür ve ilk bellek yükünü önlemez.
    /// 2:3 afişlerin yüksekliğine pay bırakılır; indirilen bayt değişmez.
    private func request(for url: URL) -> ImageRequest {
        guard let targetWidth, targetWidth > 0, targetWidth.isFinite else {
            return ImageRequest(url: url)
        }
        let pixelLimit = Float(min(2048, max(1, targetWidth * displayScale * 1.5)))

        return ImageRequest(
            url: url,
            processors: [ImageProcessors.Resize(width: targetWidth)],
            userInfo: [.thumbnailKey: ImageRequest.ThumbnailOptions(maxPixelSize: pixelLimit)]
        )
    }
}

/// Kanal logosu — kare çerçeve, yuvarlatılmış köşe, yer tutucu ikon.
public struct ChannelLogoView: View {

    private let url: URL?
    private let size: CGFloat
    private let fallbackText: String?

    public init(url: URL?, size: CGFloat = 48, fallbackText: String? = nil) {
        self.url = url
        self.size = size
        self.fallbackText = fallbackText
    }

    public var body: some View {
        RemoteImageView(url: url, targetWidth: size) {
            MediaArtworkPlaceholder(title: fallbackText, symbol: "tv", compact: true)
        }
        .frame(width: size, height: size)
        .background(Theme.Palette.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
    }
}

/// Film/dizi afişi — 2:3 oran.
public struct PosterView: View {

    private let url: URL?
    private let width: CGFloat
    private let fallbackTitle: String?

    public init(url: URL?, width: CGFloat = 110, fallbackTitle: String? = nil) {
        self.url = url
        self.width = width
        self.fallbackTitle = fallbackTitle
    }

    public var body: some View {
        RemoteImageView(url: url, contentMode: .fill, targetWidth: width) {
            MediaArtworkPlaceholder(title: fallbackTitle, symbol: "film.fill")
        }
        .frame(width: width, height: width / Theme.AspectRatio.poster)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }
}

/// Kapsayıcı genişliğini **dolduran** afiş — ızgara hücreleri için.
///
/// ⚠️ Sabit genişlikli `PosterView` uyarlanır ızgarada (`GridItem.adaptive`)
/// yanlış duruyordu: hücreler ekrana göre genişliyor ama afiş 104pt'de
/// kalıyor, iPad'de her hücrede belirgin boşluk oluşuyordu.
///
/// `Color.clear` + `aspectRatio` kalıbı kullanılıyor: önce hücre
/// genişliğinde 2:3'lük bir kutu ölçülüyor, görsel o kutuyu dolduruyor.
/// Görselin kendi boyutuna göre yerleşim yapmak, yükleme bitene kadar
/// ızgaranın zıplamasına yol açıyordu.
public struct GridPosterView: View {

    private let url: URL?
    private let cornerRadius: CGFloat
    private let fallbackTitle: String?

    public init(
        url: URL?,
        cornerRadius: CGFloat = Theme.Radius.md,
        fallbackTitle: String? = nil
    ) {
        self.url = url
        self.cornerRadius = cornerRadius
        self.fallbackTitle = fallbackTitle
    }

    public var body: some View {
        Color.clear
            .aspectRatio(Theme.AspectRatio.poster, contentMode: .fit)
            .overlay(
                RemoteImageView(
                    url: url,
                    contentMode: .fill,
                    // Izgara hücresi ekrana göre değişiyor; iPad'de bile
                    // yeterli olan sabit bir üst sınır veriliyor.
                    targetWidth: 240
                ) {
                    MediaArtworkPlaceholder(title: fallbackTitle, symbol: "film.fill")
                }
            )
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Afiş üzerine binen puan rozeti.
///
/// Referansta puan kartın köşesinde duruyor; katalogda gezerken
/// "bu iyi mi?" sorusunun cevabı detaya girmeden görünüyor.
public struct RatingBadge: View {

    private let rating: Double?

    public init(rating: Double?) {
        self.rating = rating
    }

    /// Puan yoksa veya sıfırsa rozet **hiç çizilmez** — sağlayıcıların çoğu
    /// bu alanı boş bırakıyor ve "0.0" yazan bir rozet yanıltıcı olurdu.
    /// Kontrol burada: her çağıran ayrı ayrı `if let` yazmasın.
    @ViewBuilder
    public var body: some View {
        if let rating, rating > 0 {
            HStack(spacing: 2) {
                Image(systemName: "star.fill")
                    .font(.system(size: 8, weight: .bold))
                Text(String(format: "%.1f", rating))
                    .font(Theme.Typography.badge)
            }
            .foregroundColor(Theme.Palette.warning)
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.vertical, 2)
            .background(.ultraThinMaterial, in: Capsule())
            // Yıldız ikonu + sayı ayrı ayrı okunursa anlamsız; tek etiket.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Puan \(String(format: "%.1f", rating))")
        }
    }
}
