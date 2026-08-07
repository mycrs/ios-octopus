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
                            RecentMovieCard(movie: movie) {
                                router.push(.movieDetail(movie.id))
                            }
                        }
                    }
                }
            }
            .padding(.vertical, Theme.Spacing.md)
        }
    }
}
