import SwiftUI
import OctopusDomain
import OctopusDesignSystem

/// Öne çıkan içerik kartı — ana sayfanın tepesindeki hero.
///
/// Referanstaki dönen tanıtım alanının iOS karşılığı. Orada arka plan
/// tüm ekranı kaplıyordu; burada kart hâline getirildi çünkü iOS'ta
/// altındaki raflar kaydırılabilir olmalı ve tam ekran arka plan
/// kaydırma sırasında metnin okunurluğunu bozuyor.
struct FeaturedHeroView: View {

    let movie: Movie
    let greeting: String
    let pageCount: Int
    let pageIndex: Int
    let onPlay: () -> Void
    let onDetail: () -> Void
    let onSelectPage: (Int) -> Void

    private let height: CGFloat = 280

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backdrop
            scrim
            info
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .padding(.horizontal, Theme.Spacing.md)
        .accessibilityElement(children: .contain)
    }

    private var backdrop: some View {
        RemoteImageView(
            url: movie.backdropURL ?? movie.posterURL,
            contentMode: .fill,
            // Hero kartı ekran genişliğinde; iPad'de de yeterli çözünürlük.
            targetWidth: 720
        ) {
            Theme.Palette.surfaceElevated
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        // ⚠️ Animasyon yalnızca burada, karttaki metne sızmıyor.
        //
        // Bu bilerek `HStack`/kart seviyesinde değil, yalnızca görselde:
        // referans projede de yalnızca arka plan crossfade oluyordu, başlık
        // anlık değişiyordu. Kartın tamamına animasyon verilmişti önce —
        // rotasyon sırasında VStack'in yüksekliği eski/yeni başlık için
        // farklı olduğundan iki metin bir kare boyunca üst üste bindi
        // (ekran görüntüsünde yakalandı). Metin şimdi anlık değişiyor.
        .id(movie.id)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.5), value: movie.id)
    }

    private var scrim: some View {
        LinearGradient(
            colors: [
                .black.opacity(0.15),
                .black.opacity(0.55),
                .black.opacity(0.88)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Spacer(minLength: 0)

            eyebrow
            greetingLine

            Text(movie.title)
                .font(Theme.Typography.sectionTitle)
                .foregroundColor(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            metadata
            buttons

            if pageCount > 1 { pageDots }
        }
        .padding(Theme.Spacing.md)
    }

    /// İnce çizgi + "ÖNE ÇIKAN" etiketi — referansla aynı işaret.
    private var eyebrow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Rectangle()
                .fill(Theme.Palette.accent)
                .frame(width: 20, height: 2)
                .clipShape(Capsule())

            Text("ÖNE ÇIKAN")
                .font(Theme.Typography.badge)
                .kerning(2)
                .foregroundColor(Theme.Palette.accent)
        }
    }

    private var greetingLine: some View {
        Text("\(greeting), ne izlemek istersin?")
            .font(Theme.Typography.caption)
            .foregroundColor(.white.opacity(0.75))
    }

    @ViewBuilder
    private var metadata: some View {
        let rating = movie.rating.flatMap { $0 > 0 ? String(format: "%.1f", $0) : nil }
        let genre = movie.genres.first

        if rating != nil || genre != nil {
            HStack(spacing: Theme.Spacing.sm) {
                if let rating {
                    Label(rating, systemImage: "star.fill")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Palette.warning)
                }
                if let genre, !genre.isEmpty {
                    Text(genre)
                        .font(Theme.Typography.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button(action: onPlay) {
                Label("İzle", systemImage: "play.fill")
                    .font(Theme.Typography.rowTitle)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.sm)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Palette.accent)

            Button(action: onDetail) {
                Label("Detay", systemImage: "info.circle")
                    .font(Theme.Typography.rowTitle)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
            }
            .buttonStyle(.bordered)
            .tint(.white)
        }
    }

    /// Kaçıncı içerikte olunduğunu gösterir; dönen kart kullanıcıyı
    /// şaşırtmasın diye bir sayaç gerekiyor.
    private var pageDots: some View {
        HStack(spacing: Theme.Spacing.xs) {
            // Aralık değişken; SwiftUI'ın sabit aralık kısıtına takılmamak
            // için diziye çevriliyor.
            ForEach(Array(0..<pageCount), id: \.self) { index in
                Button {
                    onSelectPage(index)
                } label: {
                    Capsule()
                        .fill(index == pageIndex ? Theme.Palette.accent : Color.white.opacity(0.3))
                        .frame(width: index == pageIndex ? 16 : 6, height: 4)
                        // Dokunma hedefi görselden büyük: 4pt'lik bir
                        // çizgiye isabet ettirmek imkânsıza yakın.
                        .padding(.vertical, Theme.Spacing.sm)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(index + 1). öne çıkan içerik")
            }
        }
        .animation(.easeInOut(duration: 0.25), value: pageIndex)
    }
}
