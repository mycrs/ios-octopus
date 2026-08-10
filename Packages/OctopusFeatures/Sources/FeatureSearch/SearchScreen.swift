import SwiftUI
import Foundation
import OctopusDomain
import OctopusDesignSystem
import OctopusNavigation

public struct SearchDependencies {
    public let playlists: PlaylistRepository
    public let channels: ChannelRepository
    public let vod: VODRepository
    public let series: SeriesRepository
    /// Kilit açıkken yetişkin içerik sonuçlardan çıkarılır.
    public let parental: ParentalControlling

    public init(
        playlists: PlaylistRepository,
        channels: ChannelRepository,
        vod: VODRepository,
        series: SeriesRepository,
        parental: ParentalControlling = OpenParentalControl()
    ) {
        self.playlists = playlists
        self.channels = channels
        self.vod = vod
        self.series = series
        self.parental = parental
    }
}

/// Birleşik arama: kanal, film ve dizi tür başlıklarıyla gruplanmış.
public struct SearchScreen: View {

    @StateObject private var viewModel: SearchViewModel
    @EnvironmentObject private var router: AppRouter
    @Environment(\.brandColor) private var brandColor

    public init(dependencies: SearchDependencies) {
        _viewModel = StateObject(wrappedValue: SearchViewModel(dependencies: dependencies))
    }

    public var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()
            content
        }
        .navigationTitle("Ara")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Kanal, film veya dizi"
        )
        .task {
            await viewModel.prepare()
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-startupSearch") {
                viewModel.searchText = "tr"
            }
#endif
        }
    }

    @ViewBuilder
    private var content: some View {
        if !viewModel.hasQuery {
            EmptyStateView(
                icon: "magnifyingglass",
                title: "Ne aramak istersin?",
                message: "Kanal, film ve dizilerde aynı anda arama yapabilirsin."
            )
        } else {
            switch viewModel.state {
            case .idle, .loading:
                ScrollView { RowListSkeleton(count: 5) }

            case .failed(let error):
                ErrorStateView(error: error)

            case .loaded:
                if viewModel.isEmpty {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "Sonuç yok",
                        message: "Farklı bir arama dene."
                    )
                } else {
                    results
                }
            }
        }
    }

    private var results: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                if !viewModel.channels.isEmpty {
                    horizontalSection(
                        title: "Canlı TV",
                        icon: "tv.fill",
                        count: viewModel.channels.count
                    ) {
                        ForEach(viewModel.channels) { channel in
                            SearchChannelCard(channel: channel) {
                                router.presentPlayer(.liveChannel(channel.id))
                            }
                        }
                    }
                }

                if !viewModel.movies.isEmpty {
                    horizontalSection(
                        title: "Filmler",
                        icon: "film.fill",
                        count: viewModel.movies.count
                    ) {
                        ForEach(viewModel.movies) { movie in
                            SearchPoster(
                                title: movie.title,
                                posterURL: movie.posterURL,
                                rating: movie.rating
                            ) {
                                router.push(.movieDetail(movie.id))
                            }
                        }
                    }
                }

                if !viewModel.series.isEmpty {
                    horizontalSection(
                        title: "Diziler",
                        icon: "rectangle.stack.fill",
                        count: viewModel.series.count
                    ) {
                        ForEach(viewModel.series) { item in
                            SearchPoster(
                                title: item.title,
                                posterURL: item.posterURL,
                                rating: item.rating
                            ) {
                                router.push(.seriesDetail(item.id))
                            }
                        }
                    }
                }
            }
            .padding(.vertical, Theme.Spacing.md)
        }
    }

    private func horizontalSection<Content: View>(
        title: String,
        icon: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(brandColor.opacity(0.14))
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(brandColor)
                }
                .frame(width: 30, height: 30)

                Text(title)
                    .font(Theme.Typography.sectionTitle)
                    .foregroundColor(Theme.Palette.textPrimary)

                Text("\(count)")
                    .font(Theme.Typography.badge)
                    .foregroundColor(brandColor)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xxs)
                    .background(brandColor.opacity(0.12))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, Theme.Spacing.md)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Theme.Spacing.md) {
                    content()
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.sm)
            }
        }
    }
}

