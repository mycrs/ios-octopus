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

    /// ⚠️ **Bellek**: sağlayıcılar 1000×1500 afiş döndürüyor. 104pt'lik bir
    /// küçük resim için tam boyutta çözmek kare başına ~6 MB demek; yüz
    /// afişlik bir ızgarada uygulama bellek baskısıyla düşüyor.
    /// Küçültme çözme (decode) sırasında yapılır — indirilen bayt aynı
    /// kalır ama bellekteki bitmap ekrandaki boyut kadar olur.
    private func request(for url: URL) -> ImageRequest {
        guard let targetWidth else { return ImageRequest(url: url) }

        return ImageRequest(
            url: url,
            processors: [ImageProcessors.Resize(width: targetWidth)]
        )
    }
}

/// Kanal logosu — kare çerçeve, yuvarlatılmış köşe, yer tutucu ikon.
public struct ChannelLogoView: View {

    private let url: URL?
    private let size: CGFloat

    public init(url: URL?, size: CGFloat = 48) {
        self.url = url
        self.size = size
    }

    public var body: some View {
        RemoteImageView(url: url, targetWidth: size) {
            ZStack {
                Theme.Palette.surfaceElevated
                Image(systemName: "tv")
                    .font(.system(size: size * 0.4))
                    .foregroundColor(Theme.Palette.textTertiary)
            }
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

    public init(url: URL?, width: CGFloat = 110) {
        self.url = url
        self.width = width
    }

    public var body: some View {
        RemoteImageView(url: url, contentMode: .fill, targetWidth: width) {
            ZStack {
                Theme.Palette.surfaceElevated
                Image(systemName: "film")
                    .font(.system(size: width * 0.3))
                    .foregroundColor(Theme.Palette.textTertiary)
            }
        }
        .frame(width: width, height: width / Theme.AspectRatio.poster)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }
}
