import SwiftUI
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
    private let placeholder: () -> Placeholder

    public init(
        url: URL?,
        contentMode: SwiftUI.ContentMode = .fit,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.contentMode = contentMode
        self.placeholder = placeholder
    }

    public var body: some View {
        if let url {
            LazyImage(url: url) { state in
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
        RemoteImageView(url: url) {
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
        RemoteImageView(url: url, contentMode: .fill) {
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
