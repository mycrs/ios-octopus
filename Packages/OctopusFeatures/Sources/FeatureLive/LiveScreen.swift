import SwiftUI
import OctopusDomain
import OctopusDesignSystem
import OctopusNavigation

public struct LiveDependencies {
    public let playlists: PlaylistRepository
    public let channels: ChannelRepository
    public let epg: EPGRepository
    public let favorites: FavoritesRepository
    /// Son izlenen kanalı bulmak için — üstteki önizleme kartı bunu kullanır.
    public let history: WatchHistoryRepository
    /// Kilit açıkken yetişkin kanallar listeden gizlenir.
    public let parental: ParentalControlling

    public init(
        playlists: PlaylistRepository,
        channels: ChannelRepository,
        epg: EPGRepository,
        favorites: FavoritesRepository,
        history: WatchHistoryRepository,
        parental: ParentalControlling = OpenParentalControl()
    ) {
        self.playlists = playlists
        self.channels = channels
        self.epg = epg
        self.favorites = favorites
        self.history = history
        self.parental = parental
    }
}

/// Canlı TV: kategori şeridi + kanal listesi + arama.
///
/// ⚠️ Bu ekran oynatıcıyı doğrudan **açmaz**; `router.presentPlayer(...)`
/// çağırır. `FeaturePlayer`'ı import etmez, bu yüzden ikisi bağımsız derlenir.
///
/// Alt bileşenler ayrı dosyalarda: `CategoryStripView.swift`, `ChannelRowView.swift`.
public struct LiveScreen: View {

    @StateObject private var viewModel: LiveChannelsViewModel
    @EnvironmentObject private var router: AppRouter

    public init(dependencies: LiveDependencies) {
        _viewModel = StateObject(wrappedValue: LiveChannelsViewModel(dependencies: dependencies))
    }

    public var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                if !viewModel.categories.isEmpty && !viewModel.isSearching {
                    CategoryStripView(
                        categories: viewModel.categories,
                        selectedID: viewModel.selectedCategoryID,
                        onSelect: viewModel.selectCategory
                    )
                }
                content
            }
        }
        .navigationTitle("Canlı TV")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Kanal ara"
        )
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingStateView(message: "Kanallar yükleniyor")

        case .failed(let error):
            ErrorStateView(error: error) {
                Task { await viewModel.load() }
            }

        case .loaded:
            if viewModel.channels.isEmpty {
                emptyState
            } else {
                channelList
            }
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: viewModel.isSearching ? "magnifyingglass" : "tv",
            title: viewModel.isSearching ? "Sonuç yok" : "Kanal yok",
            message: viewModel.isSearching
                ? "Farklı bir arama dene."
                : "Bu kaynakta kanal bulunamadı. Kaynağı güncellemeyi dene.",
            actionTitle: viewModel.isSearching ? nil : "Ayarlar'a git",
            action: viewModel.isSearching ? nil : { router.push(.about) }
        )
    }

    private var channelList: some View {
        ScrollView {
            // Arama sırasında gösterilmez: kullanıcı belirli bir kanalı
            // ararken üstte alakasız bir önizleme yer kaplamamalı.
            if !viewModel.isSearching, let lastWatched = viewModel.lastWatchedChannel {
                LiveNowPlayingCard(
                    channel: lastWatched,
                    program: viewModel.currentProgram(for: lastWatched),
                    onTap: { router.presentPlayer(.liveChannel(lastWatched.id)) }
                )
            }

            // LazyVStack: 20.000 kanallı listede yalnızca görünen satırlar
            // oluşturulur.
            LazyVStack(spacing: Theme.Spacing.xs) {
                ForEach(viewModel.channels) { channel in
                    ChannelRowView(
                        channel: channel,
                        program: viewModel.currentProgram(for: channel),
                        clock: viewModel.clock,
                        isFavorite: viewModel.isFavorite(channel),
                        onTap: { router.presentPlayer(.liveChannel(channel.id)) },
                        onToggleFavorite: { Task { await viewModel.toggleFavorite(channel) } },
                        onShowGuide: { router.push(.channelGuide(channel.id)) }
                    )
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
        }
    }
}
