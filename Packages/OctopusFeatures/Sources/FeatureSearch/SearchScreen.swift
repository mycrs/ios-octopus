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
                viewModel.searchText = "ka"
            }
#endif
        }
    }

    @ViewBuilder
    private var content: some View {
        if !viewModel.hasQuery {
            SearchWelcomeState()
        } else {
            switch viewModel.state {
            case .idle, .loading:
                SearchShelvesSkeleton()

            case .failed(let error):
                ErrorStateView(error: error)

            case .loaded:
                if viewModel.isEmpty {
                    SearchNoResultsState(
                        query: viewModel.searchText,
                        onClear: viewModel.clearSearch
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
                    SearchResultShelf(
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
                    SearchResultShelf(
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
                    SearchResultShelf(
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
        .safeAreaInset(edge: .bottom) {
            Theme.Palette.background.frame(height: 64)
        }
    }
}

