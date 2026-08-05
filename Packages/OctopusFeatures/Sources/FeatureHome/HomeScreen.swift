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
