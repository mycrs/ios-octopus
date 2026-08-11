import SwiftUI
import Foundation
import OctopusDomain
import OctopusDesignSystem
import OctopusNavigation
import OctopusPlayback

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
    @Environment(\.locale) var locale

    // Alt dosyalardaki denetim, gesture, sheet ve bölüm uzantıları bu durumu
    // paylaşır; bu nedenle dosya-özel değil modül içi görünürlüktedir.
    @State var showsControls = true
    @State var hideControlsTask: Task<Void, Never>?
    @State var isShowingTracks = false
    @State var isShowingLivePanel = false
    @State var isControlsLocked = false
    @State var nextEpisodeCountdown: Int?
    @State var nextEpisodeTask: Task<Void, Never>?
    @State var gestureNotice: PlayerGestureNotice?
    @State var gestureNoticeTask: Task<Void, Never>?

    let autoHideDelay: Duration
    let keepsControlsVisible: Bool
    let previewsPictureInPictureButton: Bool
    let previewsNextEpisodeOverlay: Bool

    public init(presentation: PlayerPresentation, dependencies: PlayerDependencies) {
#if DEBUG
        keepsControlsVisible = ProcessInfo.processInfo.arguments.contains("-keepPlayerControls")
        previewsPictureInPictureButton = ProcessInfo.processInfo.arguments.contains(
            "-previewPictureInPictureButton"
        )
        previewsNextEpisodeOverlay = ProcessInfo.processInfo.arguments.contains(
            "-previewNextEpisode"
        )
        _isControlsLocked = State(
            initialValue: ProcessInfo.processInfo.arguments.contains("-previewPlayerLock")
        )
        _isShowingLivePanel = State(
            initialValue: ProcessInfo.processInfo.arguments.contains("-previewLivePanel")
        )
        autoHideDelay = keepsControlsVisible
            ? .seconds(60)
            : .seconds(3.5)
#else
        keepsControlsVisible = false
        previewsPictureInPictureButton = false
        previewsNextEpisodeOverlay = false
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
        // Tam ekran videoda sistem çubuğu dikkati dağıtır ve VLC katmanıyla
        // titreşebilir; iOS video uygulamalarındaki gibi daima gizli tutulur.
        .statusBarHidden(true)
        .task { await viewModel.resolve() }
        .sheet(isPresented: $isShowingTracks) { trackPicker }
        .sheet(isPresented: $isShowingLivePanel) { livePanel }
        .onChange(of: controller.state, perform: handlePlaybackStateChange)
        // ⚠️ Konum normalde 5 sn'de bir yazılıyor. Kullanıcı uygulamayı
        // arka plana alıp sistem onu öldürürse son 5 saniye kaybolurdu —
        // filmi tekrar açtığında biraz geriden başlardı. Arka plana geçiş
        // "şimdi yaz" için son güvenilir an.
        .onChange(of: scenePhase) { phase in
            guard phase != .active else { return }
            Task { await controller.persistPosition() }
        }
        .onDisappear {
            nextEpisodeTask?.cancel()
            gestureNoticeTask?.cancel()
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
