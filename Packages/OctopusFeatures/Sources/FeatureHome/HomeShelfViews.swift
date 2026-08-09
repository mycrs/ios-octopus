import SwiftUI
import OctopusDomain
import OctopusDesignSystem

/// Başlıklı yatay raf.
struct ShelfView<Content: View>: View {

    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // ⚠️ Daha önce `sectionTitle` (title3/semibold) idi ve raf
            // başlıkları içeriğin önüne geçiyordu: ekranın en büyük yazısı
            // "Son eklenen filmler" oluyordu, afişler değil. Başlık artık
            // bir **etiket** gibi davranıyor.
            Text(title)
                .font(Theme.Typography.rowTitle)
                .foregroundColor(Theme.Palette.textSecondary)
                .padding(.horizontal, Theme.Spacing.md)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    content()
                }
                .padding(.horizontal, Theme.Spacing.md)
                // ⚠️ Kareyle ölçüldü: erişilebilirlik yazı boyutunda sabit
                // genişlikli kart başlıkları neredeyse tamamen kırpılıyordu
                // ("Gölg", "Son", "Kayıp"). Kartlar dekoratif bir önizleme —
                // kullanıcı dokunduğunda tam bilgiyi sınırsız boyutta
                // detay ekranında görür.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
        }
    }
}

/// "İzlemeye devam et" kartı — afiş üzerinde ilerleme çubuğu.
struct ResumeCard: View {

    let item: HomeViewModel.ResumeItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ZStack(alignment: .bottom) {
                    PosterView(url: item.posterURL, width: 104)

                    ProgressView(value: item.fraction)
                        .progressViewStyle(.linear)
                        .tint(Theme.Palette.accent)
                        .frame(width: 96, height: 2)
                        .padding(.bottom, Theme.Spacing.xs)
                }

                Text(item.title)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Palette.textPrimary)
                    .lineLimit(1)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Palette.textTertiary)
                }
            }
            .frame(width: 104, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

/// "Son izlenen kanallar" rafındaki tekil kanal.
struct RecentChannelCard: View {

    let channel: Channel
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: Theme.Spacing.xs) {
                ChannelLogoView(url: channel.logoURL, size: 64)

                Text(channel.name)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 72)
            }
        }
        .buttonStyle(.plain)
    }
}

/// "Son eklenen filmler" rafındaki tekil afiş.
struct RecentMovieCard: View {

    let movie: Movie
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                PosterView(url: movie.posterURL, width: 104)
                Text(movie.title)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Palette.textPrimary)
                    .lineLimit(2)
                    .frame(width: 104, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Son eklenen dizi kartı.
///
/// ⚠️ Film kartıyla **aynı ölçü ve ritim**: iki raf alt alta duruyor,
/// kartlar farklı boyda olsaydı sayfa dalgalı görünürdü. Ayrı bir tip
/// olmasının sebebi yalnızca farklı bir varlık (`Series`) taşıması.
struct RecentSeriesCard: View {

    let series: Series
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                PosterView(url: series.posterURL, width: 104)
                Text(series.title)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Palette.textPrimary)
                    .lineLimit(2)
                    .frame(width: 104, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}
