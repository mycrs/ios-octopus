import SwiftUI
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

    public init(
        resolver: PlaybackEngineResolver,
        streams: StreamResolving,
        progress: PlaybackProgressRepository,
        history: WatchHistoryRepository,
        channels: ChannelRepository,
        vod: VODRepository,
        series: SeriesRepository,
        parental: ParentalControlling = OpenParentalControl()
    ) {
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

    /// Denetimlerin kendiliğinden kaybolma süresi.
    let autoHideDelay: Duration = .seconds(3.5)

    public init(presentation: PlayerPresentation, dependencies: PlayerDependencies) {
        _viewModel = StateObject(
            wrappedValue: PlayerViewModel(
                dependencies: dependencies,
                source: presentation.source
            )
        )
        _controller = StateObject(
            wrappedValue: PlayerController(
                resolver: dependencies.resolver,
                progress: dependencies.progress,
                history: dependencies.history
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
        .statusBarHidden(showsControls == false)
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
        ZStack {
            // ⚠️ `.id`: motor değiştiğinde (native → VLC) yüzey baştan
            // kurulmalı; aynı görünüm yeniden kullanılırsa yeni motorun
            // katmanı hiç eklenmez ve ekran siyah kalır.
            VideoSurfaceView(makeSurface: controller.makeVideoView)
                .id(controller.engineIdentifier)
                .ignoresSafeArea()

            if case .failed(let error) = controller.state {
                playbackFailure(error, item: item)
            } else {
                controlsLayer(item)
            }
        }
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
            onClose: close
        )
    }

    func close() {
        hideControlsTask?.cancel()
        router.dismissPlayer()
    }
}
