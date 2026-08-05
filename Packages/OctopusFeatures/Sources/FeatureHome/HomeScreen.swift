import SwiftUI
import OctopusDomain
import OctopusDesignSystem
import OctopusNavigation

public struct HomeDependencies {
    public let playlists: PlaylistRepository
    public let channels: ChannelRepository
    public let vod: VODRepository
    public let series: SeriesRepository
    public let progress: PlaybackProgressRepository
    public let history: WatchHistoryRepository
    /// Kilit açıkken raflardaki yetişkin içerik gizlenir.
    ///
    /// ⚠️ "Kaldığın yer" rafı özellikle önemli: kilit kurulmadan önce
    /// izlenen bir film burada afişiyle durmaya devam ederdi.
    public let parental: ParentalControlling

    public init(
        playlists: PlaylistRepository,
        channels: ChannelRepository,
        vod: VODRepository,
        series: SeriesRepository,
        progress: PlaybackProgressRepository,
        history: WatchHistoryRepository,
        parental: ParentalControlling = OpenParentalControl()
    ) {
        self.playlists = playlists
        self.channels = channels
        self.vod = vod
        self.series = series
        self.progress = progress
        self.history = history
        self.parental = parental
    }
}

/// Ana sayfa: yatay raflar.
public struct HomeScreen: View {

    @StateObject private var viewModel: HomeViewModel
    @EnvironmentObject private var router: AppRouter

    public init(dependencies: HomeDependencies) {
        _viewModel = StateObject(wrappedValue: HomeViewModel(dependencies: dependencies))
    }

    public var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()
            content
        }
        .navigationTitle("Ana Sayfa")
        .navigationBarTitleDisplayMode(.inline)
        // Ekrana her dönüşte tazelenir: kullanıcı bir bölüm izleyip
        // geri geldiğinde "devam et" rafı güncel olmalı.
        .task { await viewModel.load() }
        // Ayrı görev: ekrandan çıkılınca iptal edilir, döngü arka planda
        // boşuna dönmez.
        .task { await viewModel.rotateFeatured() }
        .refreshable { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingStateView()

        case .failed(let error):
            ErrorStateView(error: error) { Task { await viewModel.load() } }

        case .loaded:
            if viewModel.isEmpty {
                EmptyStateView(
                    icon: "house",
                    title: "Henüz içerik yok",
                    message: "İzlemeye başladığında burada kaldığın yerden devam edebilirsin.",
                    actionTitle: "Canlı TV'ye git",
                    action: { router.switchTab(to: .live) }
                )
            } else {
                shelves
            }
        }
    }

    private var shelves: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                if let item = viewModel.featuredItem {
                    FeaturedHeroView(
                        movie: item,
                        greeting: viewModel.greeting,
                        pageCount: viewModel.featured.count,
                        pageIndex: viewModel.featuredIndex,
                        onPlay: { router.presentPlayer(.movie(item.id)) },
                        onDetail: { router.push(.movieDetail(item.id)) },
                        onSelectPage: viewModel.showFeatured(at:)
                    )
                    // Kart değişince yumuşak geçiş; ani sıçrama göz yorar.
                    .animation(.easeInOut(duration: 0.45), value: viewModel.featuredIndex)
                }

                if !viewModel.resumeItems.isEmpty {
                    ShelfView(title: "İzlemeye devam et") {
                        ForEach(viewModel.resumeItems) { item in
                            ResumeCard(item: item) {
                                router.presentPlayer(item.source)
                            }
                        }
                    }
                }

                if !viewModel.recentChannels.isEmpty {
                    ShelfView(title: "Son izlenen kanallar") {
                        ForEach(viewModel.recentChannels) { channel in
                            RecentChannelCard(channel: channel) {
                                router.presentPlayer(.liveChannel(channel.id))
                            }
                        }
                    }
                }

                if !viewModel.recentlyAdded.isEmpty {
                    ShelfView(title: "Son eklenen filmler") {
                        ForEach(viewModel.recentlyAdded) { movie in
                            Button {
                                router.push(.movieDetail(movie.id))
                            } label: {
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
                }
            }
            .padding(.vertical, Theme.Spacing.md)
        }
    }
}

/// Başlıklı yatay raf.
private struct ShelfView<Content: View>: View {

    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.sectionTitle)
                .foregroundColor(Theme.Palette.textPrimary)
                .padding(.horizontal, Theme.Spacing.md)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    content()
                }
                .padding(.horizontal, Theme.Spacing.md)
            }
        }
    }
}

/// "İzlemeye devam et" kartı — afiş üzerinde ilerleme çubuğu.
private struct ResumeCard: View {

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

private struct RecentChannelCard: View {

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

/// Öne çıkan içerik kartı — ana sayfanın tepesindeki hero.
///
/// Referanstaki dönen tanıtım alanının iOS karşılığı. Orada arka plan
/// tüm ekranı kaplıyordu; burada kart hâline getirildi çünkü iOS'ta
/// altındaki raflar kaydırılabilir olmalı ve tam ekran arka plan
/// kaydırma sırasında metnin okunurluğunu bozuyor.
private struct FeaturedHeroView: View {

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
        RemoteImageView(url: movie.backdropURL ?? movie.posterURL, contentMode: .fill) {
            Theme.Palette.surfaceElevated
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        // Görselin kimliği yansısın ama metin önde kalsın.
        .id(movie.id)
        .transition(.opacity)
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
