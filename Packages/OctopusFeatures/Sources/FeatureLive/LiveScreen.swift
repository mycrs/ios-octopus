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

/// Canlı TV: üstte gömülü önizleme, altında kategori şeridi, arama ve liste.
///
/// ## Yerleşim referansla aynı
/// Referans uygulamada sıra şöyle: **video → kategoriler → arama → liste**,
/// ve video ekranın üst kenarına yapışık. Burada da öyle:
/// - Gezinme çubuğu **gizli** — önizleme kartı durum çubuğunun altına uzansın
///   (bu yüzden bu sekmede arama/ayarlar ikonu da görünmez; ayarlara diğer
///   sekmelerin üst barından erişiliyor).
/// - Arama kutusu `.searchable` yerine kendi alanımız: `.searchable` aramayı
///   gezinme çubuğuna koyuyor, biz kategorilerin **altında** istiyoruz.
///
/// ⚠️ Bu ekran oynatıcıyı doğrudan **açmaz**; `router.presentPlayer(...)`
/// çağırır. `FeaturePlayer`'ı import etmez, bu yüzden ikisi bağımsız derlenir.
///
/// Alt bileşenler ayrı dosyalarda: `CategoryStripView.swift`,
/// `ChannelRowView.swift`, `LiveNowPlayingCard.swift`.
public struct LiveScreen: View {

    @StateObject private var viewModel: LiveChannelsViewModel
    @EnvironmentObject private var router: AppRouter

    public init(dependencies: LiveDependencies) {
        _viewModel = StateObject(wrappedValue: LiveChannelsViewModel(dependencies: dependencies))
    }

    /// Önizleme kartı görünüyor mu?
    ///
    /// Arama sırasında gizlenir: kullanıcı belirli bir kanalı ararken üstte
    /// alakasız bir önizleme yer kaplamamalı.
    private var showsPreview: Bool {
        !viewModel.isSearching && viewModel.lastWatchedChannel != nil
    }

    public var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                if showsPreview, let lastWatched = viewModel.lastWatchedChannel {
                    LiveNowPlayingCard(
                        channel: lastWatched,
                        program: viewModel.currentProgram(for: lastWatched),
                        onTap: { router.presentPlayer(.liveChannel(lastWatched.id)) }
                    )
                }

                // ⚠️ Arama sırasında da görünür kalır. Eskiden gizleniyordu
                // ama arama kutusu artık kategorilerin **altında**; gizlemek
                // kullanıcı yazmaya başlar başlamaz kutuyu yukarı zıplatırdı.
                // Referansta da şerit her zaman duruyor.
                if !viewModel.categories.isEmpty {
                    CategoryStripView(
                        categories: viewModel.categories,
                        selectedID: viewModel.selectedCategoryID,
                        onSelect: viewModel.selectCategory
                    )
                }

                SearchField(text: $viewModel.searchText, placeholder: "Kanal ara")
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.sm)
                    // Önizleme yokken kategori şeridi üstte kalıyor ve arama
                    // ona yapışıyor; araya nefes payı gerekiyor.
                    .padding(.top, showsPreview ? Theme.Spacing.sm : 0)

                content
            }
        }
        // Kart yokken üst güvenli alan korunur — aksi hâlde kategori şeridi
        // durum çubuğunun altında kalırdı.
        .ignoresSafeArea(edges: showsPreview ? .top : [])
        .toolbar(.hidden, for: .navigationBar)
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
            // ⚠️ Önizleme kartı burada **değil**: referansta video sabit
            // duruyor, liste onun altında kayıyor. Kart artık `body`'de,
            // ScrollView'in dışında.
            //
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
