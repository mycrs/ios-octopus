import SwiftUI
import OctopusDomain
import OctopusDesignSystem

/// Başlıklı yatay raf.
struct ShelfView<Content: View>: View {

    let title: String
    @ViewBuilder let content: () -> Content
    @Environment(\.brandColor) private var brandColor

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Capsule()
                    .fill(brandColor)
                    .frame(width: 3, height: 18)

                Text(title)
                    .font(Theme.Typography.sectionTitle)
                    .foregroundColor(Theme.Palette.textPrimary)

                Spacer(minLength: 0)
            }
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
    @Environment(\.brandColor) private var brandColor

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ZStack(alignment: .bottom) {
                    PosterView(url: item.posterURL, width: 112)
                        .homePosterChrome()

                    ProgressView(value: item.fraction)
                        .progressViewStyle(.linear)
                        .tint(brandColor)
                        .frame(width: 104, height: 2)
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
            .frame(width: 112, alignment: .leading)
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
            VStack(spacing: Theme.Spacing.sm) {
                ChannelLogoView(url: channel.logoURL, size: 68)

                Text(channel.name)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 82)
            }
            .padding(Theme.Spacing.sm)
            .frame(width: 98)
            .frame(minHeight: 116)
            .background(Theme.Palette.surface.opacity(0.68))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
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
                PosterView(url: movie.posterURL, width: 112)
                    .homePosterChrome()
                Text(movie.title)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Palette.textPrimary)
                    .lineLimit(2)
                    .frame(width: 112, alignment: .leading)
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
                PosterView(url: series.posterURL, width: 112)
                    .homePosterChrome()
                Text(series.title)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Palette.textPrimary)
                    .lineLimit(2)
                    .frame(width: 112, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    func homePosterChrome() -> some View {
        overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.24), radius: 10, y: 6)
    }
}
