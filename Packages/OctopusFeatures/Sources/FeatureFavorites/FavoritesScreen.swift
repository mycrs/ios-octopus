import SwiftUI
import OctopusDomain
import OctopusDesignSystem
import OctopusNavigation

public struct FavoritesDependencies {
    public let playlists: PlaylistRepository
    public let favorites: FavoritesRepository
    /// Yetişkin içerik favorilenmiş olabilir; kilit açıkken o da gizlenir.
    public let parental: ParentalControlling

    public init(
        playlists: PlaylistRepository,
        favorites: FavoritesRepository,
        parental: ParentalControlling = OpenParentalControl()
    ) {
        self.playlists = playlists
        self.favorites = favorites
        self.parental = parental
    }
}

/// Favoriler: kanal, film ve dizi bölümlü tek liste.
public struct FavoritesScreen: View {

    @StateObject private var viewModel: FavoritesViewModel
    @EnvironmentObject private var router: AppRouter

    private let posterColumns = [
        GridItem(.adaptive(minimum: 104), spacing: Theme.Spacing.md)
    ]

    public init(dependencies: FavoritesDependencies) {
        _viewModel = StateObject(wrappedValue: FavoritesViewModel(dependencies: dependencies))
    }

    public var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()
            content
        }
        .navigationTitle("Favoriler")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ScrollView { PosterGridSkeleton(count: 6) }

        case .failed(let error):
            ErrorStateView(error: error) { Task { await viewModel.load() } }

        case .loaded:
            if viewModel.isEmpty {
                // Boş ekranda kullanıcıyı bırakmak yerine başlayacağı yere gönder.
                EmptyStateView(
                    icon: "heart",
                    title: "Favori yok",
                    message: "Kanal, film ve dizileri kalp simgesiyle favorilerine ekleyebilirsin.",
                    actionTitle: "Canlı TV'ye git",
                    action: { router.switchTab(to: .live) }
                )
            } else {
                list
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                if !viewModel.channels.isEmpty {
                    section(title: "Kanallar") {
                        VStack(spacing: Theme.Spacing.xs) {
                            ForEach(viewModel.channels) { channel in
                                FavoriteChannelRow(
                                    channel: channel,
                                    onTap: { router.presentPlayer(.liveChannel(channel.id)) },
                                    onRemove: { Task { await viewModel.removeChannel(channel) } }
                                )
                            }
                        }
                    }
                }

                if !viewModel.movies.isEmpty {
                    section(title: "Filmler") {
                        LazyVGrid(columns: posterColumns, spacing: Theme.Spacing.lg) {
                            ForEach(viewModel.movies) { movie in
                                FavoritePoster(
                                    title: movie.title,
                                    posterURL: movie.posterURL,
                                    onTap: { router.push(.movieDetail(movie.id)) },
                                    onRemove: { Task { await viewModel.removeMovie(movie) } }
                                )
                            }
                        }
                    }
                }

                if !viewModel.series.isEmpty {
                    section(title: "Diziler") {
                        LazyVGrid(columns: posterColumns, spacing: Theme.Spacing.lg) {
                            ForEach(viewModel.series) { item in
                                FavoritePoster(
                                    title: item.title,
                                    posterURL: item.posterURL,
                                    onTap: { router.push(.seriesDetail(item.id)) },
                                    onRemove: { Task { await viewModel.removeSeries(item) } }
                                )
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
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.sectionTitle)
                .foregroundColor(Theme.Palette.textPrimary)
            content()
        }
    }
}

private struct FavoriteChannelRow: View {

    let channel: Channel
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.md) {
                ChannelLogoView(url: channel.logoURL, size: 40)

                Text(channel.name)
                    .font(Theme.Typography.rowTitle)
                    .foregroundColor(Theme.Palette.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button(action: onRemove) {
                    Image(systemName: "heart.fill")
                        .foregroundColor(Theme.Palette.live)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Favorilerden çıkar")
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct FavoritePoster: View {

    let title: String
    let posterURL: URL?
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                GridPosterView(url: posterURL)

                Text(title)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive, action: onRemove) {
                Label("Favorilerden çıkar", systemImage: "heart.slash")
            }
        }
    }
}
