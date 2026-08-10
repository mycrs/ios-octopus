import SwiftUI
import Foundation
import OctopusDomain
import OctopusDesignSystem
import OctopusNavigation
import OctopusPlayback

public struct PlayerDependencies {
    public let resolver: PlaybackEngineResolver
    public let streams: StreamResolving
    public let progress: PlaybackProgressRepository
    public let history: WatchHistoryRepository
    public let channels: ChannelRepository
    public let vod: VODRepository
    public let series: SeriesRepository

    /// ⚠️ Oynatıcı da kilidi uygulamak **zorunda**: kanal değiştirme
    /// listesi süzülmezse kullanıcı zaplayarak yetişkin bir kanala
    /// düşebilir — kilit o yoldan atlatılmış olur.
    public let parental: ParentalControlling

    /// Kullanıcının Ayarlar'daki oynatma tercihleri.
    public let preferences: PlaybackPreferences?

    public init(
        resolver: PlaybackEngineResolver,
        streams: StreamResolving,
        progress: PlaybackProgressRepository,
        history: WatchHistoryRepository,
        channels: ChannelRepository,
        vod: VODRepository,
        series: SeriesRepository,
        preferences: PlaybackPreferences? = nil,
        parental: ParentalControlling = OpenParentalControl()
    ) {
        self.preferences = preferences
        self.resolver = resolver
        self.streams = streams
        self.progress = progress
        self.history = history
        self.channels = channels
        self.vod = vod
        self.series = series
        self.parental = parental
    }
}

/// Tam ekran oynatıcı.
///
/// ⚠️ Bu ekran **hangi motorun** çalıştığını bilmez. `PlaybackEngineResolver`
/// karar verir, `PlayerController` yürütür, video yüzeyi motordan gelir.
/// AVPlayer'dan VLC'ye düşüş burada değil, koordinatörde yönetilir —
/// bu dosyada ne AVFoundation ne VLCKit adı geçer.
///
/// Alt bileşenler ayrı dosyalarda: `PlayerControlsOverlay`, `PlayerScrubBar`,
/// `PlayerTrackPicker`, `VideoSurfaceView`.
public struct PlayerScreen: View {

    @StateObject var viewModel: PlayerViewModel
    @StateObject var controller: PlayerController
    @EnvironmentObject private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase

    // ⚠️ Bu üçü `private` değil: denetim mantığı `PlayerScreen+Controls.swift`
    // içinde ve Swift'te `private`, **aynı dosyadaki** uzantılardan erişilebilir.
    // Ayrı dosyaya taşınınca modül içi görünürlük gerekiyor.
    @State var showsControls = true
    @State var hideControlsTask: Task<Void, Never>?
    @State var isShowingTracks = false

    let autoHideDelay: Duration
    let keepsControlsVisible: Bool

    public init(presentation: PlayerPresentation, dependencies: PlayerDependencies) {
#if DEBUG
        keepsControlsVisible = ProcessInfo.processInfo.arguments.contains("-keepPlayerControls")
        autoHideDelay = keepsControlsVisible
            ? .seconds(60)
            : .seconds(3.5)
#else
        keepsControlsVisible = false
        autoHideDelay = .seconds(3.5)
#endif
        _viewModel = StateObject(
            wrappedValue: PlayerViewModel(
                dependencies: dependencies,
                source: presentation.source,
                startAt: presentation.startAt
            )
        )
        _controller = StateObject(
            wrappedValue: PlayerController(
                resolver: dependencies.resolver,
                progress: dependencies.progress,
                history: dependencies.history,
                preferences: dependencies.preferences
            )
        )
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
        }
        // Oynatıcı her zaman koyu; sistem teması burada geçersiz.
        .preferredColorScheme(.dark)
        .statusBarHidden(keepsControlsVisible ? false : showsControls == false)
        .task { await viewModel.resolve() }
        .sheet(isPresented: $isShowingTracks) { trackPicker }
        // ⚠️ Konum normalde 5 sn'de bir yazılıyor. Kullanıcı uygulamayı
        // arka plana alıp sistem onu öldürürse son 5 saniye kaybolurdu —
        // filmi tekrar açtığında biraz geriden başlardı. Arka plana geçiş
        // "şimdi yaz" için son güvenilir an.
        .onChange(of: scenePhase) { phase in
            guard phase != .active else { return }
            Task { await controller.persistPosition() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .resolving:
            LoadingStateView(message: "Yayın hazırlanıyor")

        case .failed(let message):
            resolveFailure(message)

        case .ready(let item):
            playback(item)
        }
    }

    // MARK: - Oynatma

    private func playback(_ item: PlaybackItem) -> some View {
        PlayerSurfaceContainer(makeSurface: controller.makeVideoView,
                               surfaceGeneration: controller.surfaceGeneration) {
            if case .failed(let error) = controller.state {
                playbackFailure(error, item: item)
            } else {
                controlsLayer(item)
            }
        }
        .ignoresSafeArea()
        // ⚠️ `id:` şart — kanal zaplanınca `item` değişiyor ve oynatmanın
        // yeniden başlaması gerekiyor. Kimliksiz `.task` yalnızca görünüm
        // ilk kurulduğunda çalışır; kullanıcı sonraki kanala geçince ekran
        // eski yayında donup kalırdı.
        .task(id: item.url) {
            await controller.start(item)
            scheduleControlsHide()
        }
        .onDisappear {
            hideControlsTask?.cancel()
            // Motoru bırakmak ve son konumu yazmak: ikisi de atlanamaz.
            // Ekran kapanırken görev iptal edilmesin diye `Task.detached`
            // değil, controller'ın kendi ömrüne bağlı bir görev kullanılıyor.
            Task { await controller.finish() }
        }
    }

    // MARK: - Hatalar

    /// Adres üretilemedi — sorun oynatıcıdan **önce**.
    private func resolveFailure(_ message: String) -> some View {
        EmptyStateView(
            icon: "exclamationmark.triangle",
            title: "Yayın adresi alınamadı",
            message: message,
            actionTitle: "Kapat",
            action: close
        )
    }

    /// Adres üretildi ama açılamadı — sorun akışta ya da motorda.
    /// İçeriği `PlaybackErrorView` çiziyor.
    private func playbackFailure(_ error: AppError, item: PlaybackItem) -> some View {
        PlaybackErrorView(
            error: error,
            item: item,
            onRetry: { Task { await controller.start(item) } },
            onClose: close,
            onPreviousChannel: item.isLive && viewModel.canZap
                ? { Task { await viewModel.zap(by: -1) } }
                : nil,
            onNextChannel: item.isLive && viewModel.canZap
                ? { Task { await viewModel.zap(by: 1) } }
                : nil
        )
    }

    func close() {
        hideControlsTask?.cancel()
        router.dismissPlayer()
    }
}
