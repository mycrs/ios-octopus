import SwiftUI
import OctopusDomain
import OctopusDesignSystem
import OctopusNavigation

public struct SearchDependencies {
    public let playlists: PlaylistRepository
    public let channels: ChannelRepository
    public let vod: VODRepository
    public let series: SeriesRepository

    public init(
        playlists: PlaylistRepository,
        channels: ChannelRepository,
        vod: VODRepository,
        series: SeriesRepository
    ) {
        self.playlists = playlists
        self.channels = channels
        self.vod = vod
        self.series = series
    }
}

/// Birleşik arama: kanal, film ve dizi tür başlıklarıyla gruplanmış.
public struct SearchScreen: View {

    @StateObject private var viewModel: SearchViewModel
    @EnvironmentObject private var router: AppRouter

    private let posterColumns = [
        GridItem(.adaptive(minimum: 104), spacing: Theme.Spacing.md)
    ]

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
        .task { await viewModel.prepare() }
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
                LoadingStateView()

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
                    section(title: "Kanallar", count: viewModel.channels.count) {
                        VStack(spacing: Theme.Spacing.xs) {
                            ForEach(viewModel.channels) { channel in
                                SearchChannelRow(channel: channel) {
                                    router.presentPlayer(.liveChannel(channel.id))
                                }
                            }
                        }
                    }
                }

                if !viewModel.movies.isEmpty {
                    section(title: "Filmler", count: viewModel.movies.count) {
                        LazyVGrid(columns: posterColumns, spacing: Theme.Spacing.lg) {
                            ForEach(viewModel.movies) { movie in
                                SearchPoster(title: movie.title, posterURL: movie.posterURL) {
                                    router.push(.movieDetail(movie.id))
                                }
                            }
                        }
                    }
                }

                if !viewModel.series.isEmpty {
                    section(title: "Diziler", count: viewModel.series.count) {
                        LazyVGrid(columns: posterColumns, spacing: Theme.Spacing.lg) {
                            ForEach(viewModel.series) { item in
                                SearchPoster(title: item.title, posterURL: item.posterURL) {
                                    router.push(.seriesDetail(item.id))
                                }
                            }
                        }
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
    }

    private func section<Content: View>(
        title: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(title)
                    .font(Theme.Typography.sectionTitle)
                    .foregroundColor(Theme.Palette.textPrimary)

                Text("\(count)")
                    .font(Theme.Typography.badge)
                    .foregroundColor(Theme.Palette.accent)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xxs)
                    .background(Theme.Palette.accentMuted)
                    .clipShape(Capsule())
            }
            content()
        }
    }
}

private struct SearchChannelRow: View {

    let channel: Channel
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.md) {
                ChannelLogoView(url: channel.logoURL, size: 40)

                Text(channel.name)
                    .font(Theme.Typography.rowTitle)
                    .foregroundColor(Theme.Palette.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: "play.circle")
                    .foregroundColor(Theme.Palette.textTertiary)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct SearchPoster: View {

    let title: String
    let posterURL: URL?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                PosterView(url: posterURL, width: 104)

                Text(title)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: 104, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}
