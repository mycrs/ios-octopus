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

/// Ana sayfa: öne çıkan içerik + yatay raflar.
///
/// Alt bileşenler ayrı dosyalarda: `FeaturedHeroView.swift` (tepedeki hero
/// kartı), `HomeShelfViews.swift` (raf ve kart görünümleri).
public struct HomeScreen: View {

    @StateObject private var viewModel: HomeViewModel
    @EnvironmentObject private var router: AppRouter
    /// Bayi adı ve vurgu rengi başlıktan okunuyor.
    @EnvironmentObject private var theme: ThemeController

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
        .refreshable { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            // Spinner yerine gelecek düzenin iskeleti: içerik gelince
            // yalnızca içi dolar, yerleşim zıplamaz.
            ScrollView { ShelvesSkeleton() }

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
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                // ⚠️ Burada eskiden **dönen tanıtım afişi** vardı; kaldırıldı.
                // Ana sayfanın tepesi "neredeyim, hesabım ne durumda"
                // sorusunu cevaplamalı — içerik zaten altındaki raflarda
                // ve orada kullanıcı ne göreceğini seçebiliyor.
                HomeHeaderView(
                    account: viewModel.account,
                    greeting: viewModel.greeting,
                    brandName: theme.resellerName
                )

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
                            RecentMovieCard(movie: movie) {
                                router.push(.movieDetail(movie.id))
                            }
                        }
                    }
                }

                if !viewModel.recentSeries.isEmpty {
                    ShelfView(title: "Son eklenen diziler") {
                        ForEach(viewModel.recentSeries) { series in
                            RecentSeriesCard(series: series) {
                                router.push(.seriesDetail(series.id))
                            }
                        }
                    }
                }
            }
            // Hero kenara **ve** üste yapışık; alttaki raflar için nefes payı.
            .padding(.bottom, Theme.Spacing.lg)
        }
    }
}
