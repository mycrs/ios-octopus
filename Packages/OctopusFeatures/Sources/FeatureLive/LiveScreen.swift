import SwiftUI
import OctopusDomain
import OctopusDesignSystem
import OctopusNavigation
import OctopusPlayback

public struct LiveDependencies {
    public let playlists: PlaylistRepository
    public let channels: ChannelRepository
    public let epg: EPGRepository
    public let favorites: FavoritesRepository
    /// Son izlenen kanalı bulmak için — hiçbir şey oynamıyorken tepede durur.
    public let history: WatchHistoryRepository
    /// Kilit açıkken yetişkin kanallar listeden gizlenir.
    public let parental: ParentalControlling

    /// Gömülü mini oynatıcının ihtiyaç duyduğu iki parça.
    ///
    /// ⚠️ Bunlar `FeaturePlayer`'dan **gelmiyor**: motor sözleşmesi
    /// `OctopusPlayback`'te, adres çözümü Domain'de. İki ekran birbirini
    /// görmüyor (bkz. CLAUDE.md demir kural 3).
    public let resolver: PlaybackEngineResolver
    public let streams: StreamResolving
    /// Canlı yayında konum kaydedilmez ama denetleyici sözleşmesi ister.
    public let progress: PlaybackProgressRepository

    /// Kullanıcının Ayarlar'daki oynatma tercihleri — mini oynatıcı da
    /// tam ekran oynatıcıyla aynı tampon/yerleşim ayarlarını kullanmalı.
    public let preferences: PlaybackPreferences?

    /// Tam ekran oynatıcıyla **paylaşılan** denetleyici.
    ///
    /// ⚠️ Paylaşım şart: ayrı örneklerle tam ekrana geçmek motoru bırakıp
    /// yeniden bağlanmak demekti ve kullanıcı her geçişte siyah ekran
    /// görüyordu. Tek örnekle yayın kesintisiz sürüyor, yalnızca video
    /// yüzeyi yer değiştiriyor. Somut tip yine `AppContainer`'da üretilir.
    public let controller: PlayerController

    public init(
        playlists: PlaylistRepository,
        channels: ChannelRepository,
        epg: EPGRepository,
        favorites: FavoritesRepository,
        history: WatchHistoryRepository,
        resolver: PlaybackEngineResolver,
        streams: StreamResolving,
        progress: PlaybackProgressRepository,
        controller: PlayerController,
        preferences: PlaybackPreferences? = nil,
        parental: ParentalControlling = OpenParentalControl()
    ) {
        self.controller = controller
        self.preferences = preferences
        self.playlists = playlists
        self.channels = channels
        self.epg = epg
        self.favorites = favorites
        self.history = history
        self.resolver = resolver
        self.streams = streams
        self.progress = progress
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
    /// ⚠️ `@StateObject` **değil**: denetleyici bu ekrana ait değil,
    /// tam ekran oynatıcıyla paylaşılıyor ve ömrü `AppContainer`'da.
    /// `@StateObject` yapılsaydı ekran her kurulduğunda yeni bir motor
    /// üretilir, paylaşımın amacı ortadan kalkardı.
    @ObservedObject private var controller: PlayerController
    @EnvironmentObject private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase

    public init(dependencies: LiveDependencies) {
        _viewModel = StateObject(wrappedValue: LiveChannelsViewModel(dependencies: dependencies))
        _controller = ObservedObject(wrappedValue: dependencies.controller)
    }

    /// Üstteki oynatıcı alanı görünüyor mu?
    ///
    /// Arama sırasında gizlenir: kullanıcı belirli bir kanalı ararken üstte
    /// yer kaplamamalı. **Oynatma sürerken gizlenmez** — arama yapmak için
    /// yayını kesmek referanstaki davranışa aykırı olurdu.
    private var showsPreview: Bool {
        if viewModel.playingChannel != nil { return true }
        return !viewModel.isSearching && viewModel.lastWatchedChannel != nil
    }

    public var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                if showsPreview {
                    LiveMiniPlayerView(
                        channel: viewModel.playingChannel,
                        program: (viewModel.playingChannel ?? viewModel.lastWatchedChannel)
                            .flatMap(viewModel.currentProgram),
                        controller: controller,
                        placeholderChannel: viewModel.lastWatchedChannel,
                        // Tam ekran kapalıyken yüzeyin sahibi burasıdır.
                        ownsSurface: router.player == nil,
                        onExpand: expandToFullScreen
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
        // ⚠️ Üst güvenli alan **korunuyor**. Eskiden oynatıcı durum
        // çubuğunun altına uzanıyordu ("kenara yapışık" görünsün diye) ama
        // yüksekliğinin ~60pt'si oraya gidiyordu: geriye dar bir video
        // şeridi kalıyordu. Referansta da video durum çubuğunun **altından**
        // başlıyor. Artık tam 16:9'un tamamı görünür.
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.load() }
        // ⚠️ Motoru bırakmak **atlanamaz**: IPTV panelleri eşzamanlı
        // bağlantıyı sınırlar ve bırakılmayan her akış kotadan bir hak yer
        // (bkz. PlaybackEngine.teardown). Sekme değişince de tetiklenir.
        .onDisappear {
            // ⚠️ Tam ekrana devrederken bırakma: `fullScreenCover` açılınca
            // bu ekran da "kayboldu" sayılıyor ve koşulsuz `finish()`
            // devraldığımız yayını hemen öldürürdü.
            guard router.player == nil else { return }
            Task {
                await controller.finish()
                viewModel.clearPlayingChannel()
            }
        }
        // Arka plana geçince gömülü yayın durur: kullanıcı Canlı TV
        // listesine bakarken sesin arka planda sürmesini beklemez —
        // arka plan sesi tam ekran oynatıcının işi.
        .onChange(of: scenePhase) { phase in
            // Tam ekran açıkken oynatmanın sahibi o ekran: arka plan sesi
            // orada **isteniyor**, burada duraklatmak onu susturur.
            guard router.player == nil else { return }
            guard viewModel.playingChannel != nil else { return }
            if phase == .active {
                // Mini oynatıcıda ayrı bir oynat düğmesi yok. Arka plan için
                // bizim duraklattığımız yayın dönüşte sessizce devam etmeli.
                controller.play()
            } else {
                controller.pause()
            }
        }
        .overlay(alignment: .bottom) { playbackMessage }
    }

    /// Akış açılamadıysa listeyi bozmadan uyarır.
    @ViewBuilder
    private var playbackMessage: some View {
        if let message = viewModel.playbackMessage {
            InlineMessageView(text: message, kind: .error)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.md)
        }
    }

    // MARK: - Gömülü oynatma

    /// Kanalı üstteki mini oynatıcıda başlatır.
    private func play(_ channel: Channel) {
        Haptics.selection()
        Task {
            guard let item = await viewModel.playbackItem(for: channel) else { return }
            await controller.start(item)
        }
    }

    /// Tam ekrana geçer.
    ///
    /// ⚠️ Motor **bırakılmıyor** — kasıtlı. Eskiden burada `finish()`
    /// çağrılıyordu (gerekçe: iki oynatıcı açık kalırsa panelde iki
    /// bağlantı tutulur). Denetleyici artık tam ekranla paylaşıldığı için
    /// ortada tek motor var, dolayısıyla ikinci bağlantı riski yok;
    /// bırakmak yalnızca yayını gereksizce sıfırdan açtırıyordu.
    /// Tam ekran aynı yayını devralır (`PlayerController.start` aynı
    /// canlı akış için etkisizdir), geçiş kesintisiz olur.
    private func expandToFullScreen() {
        guard let channel = viewModel.playingChannel ?? viewModel.lastWatchedChannel else { return }
        router.presentPlayer(.liveChannel(channel.id))
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ScrollView { RowListSkeleton() }

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
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear.frame(height: 0).id(channelListTopID)

                // LazyVStack: büyük listelerde yalnızca görünen satırlar kurulur.
                LazyVStack(spacing: Theme.Spacing.xs) {
                    ForEach(viewModel.channels) { channel in
                        ChannelRowView(
                            channel: channel,
                            program: viewModel.currentProgram(for: channel),
                            clock: viewModel.clock,
                            isFavorite: viewModel.isFavorite(channel),
                            onTap: { play(channel) },
                            onToggleFavorite: { Task { await viewModel.toggleFavorite(channel) } },
                            onShowGuide: { router.push(.channelGuide(channel.id)) }
                        )
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .onChange(of: viewModel.selectedCategoryID) { _ in
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo(channelListTopID, anchor: .top)
                }
            }
        }
        .padding(.bottom, Theme.Layout.tabBarClearance)
    }

    private var channelListTopID: String { "live-channel-list-top" }
}
