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
    @ObservedObject var controller: PlayerController
    @EnvironmentObject private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) var locale

    // Alt dosyalardaki denetim, gesture, sheet ve bölüm uzantıları bu durumu
    // paylaşır; bu nedenle dosya-özel değil modül içi görünürlüktedir.
    @State var showsControls = true
    @State var hideControlsTask: Task<Void, Never>?
    /// Açık iz seçicinin odağı; `nil` ise kapalı.
    @State var trackPickerFocus: PlayerTrackPicker.Focus?
    @State var isShowingLivePanel = false
    @State var isControlsLocked = false
    @State var nextEpisodeSession = NextEpisodeSession()
    @State var isShowingNextEpisodePrompt = false
    @State var gestureNotice: PlayerGestureNotice?
    @State var gestureNoticeTask: Task<Void, Never>?
    @State private var ownedSession: PlayerController.Session?
    private let presentation: PlayerPresentation

    let autoHideDelay: Duration
    let keepsControlsVisible: Bool
    let previewsPictureInPictureButton: Bool
    let previewsNextEpisodeOverlay: Bool

    public init(presentation: PlayerPresentation, dependencies: PlayerDependencies) {
        self.presentation = presentation
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
        // ⚠️ `@StateObject` **değil**: denetleyici Canlı TV'deki mini
        // oynatıcıyla paylaşılıyor ve ömrü `AppContainer`'da. Burada yeni
        // bir örnek üretmek, tam ekrana her geçişte yayını sıfırdan
        // açtırıyordu — kullanıcının gördüğü "tekrar bağlanıyor" buydu.
        _controller = ObservedObject(wrappedValue: dependencies.controller)
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
        .sheet(item: $trackPickerFocus) { trackPicker($0) }
        .overlay { if isShowingLivePanel { livePanel } }
        .onChange(of: controller.state, perform: handlePlaybackStateChange)
        .onChange(of: controller.session) { session in
            guard router.player?.id == presentation.id else { return }
            ownedSession = session
        }
        // ⚠️ Konum normalde 5 sn'de bir yazılıyor. Kullanıcı uygulamayı
        // arka plana alıp sistem onu öldürürse son 5 saniye kaybolurdu —
        // filmi tekrar açtığında biraz geriden başlardı. Arka plana geçiş
        // "şimdi yaz" için son güvenilir an.
        .onChange(of: scenePhase) { phase in
            guard phase != .active else { return }
            let session = controller.session
            Task {
                guard controller.session == session else { return }
                await controller.persistPosition()
                guard router.player?.id == presentation.id else { return }
                guard await viewModel.lockAndValidateCurrentSource() else {
                    guard controller.session == session else { return }
                    if let session { controller.stop(ifCurrent: session) }
                    router.dismissPlayer(ifPresented: presentation.id)
                    return
                }
            }
        }
        .onDisappear {
            gestureNoticeTask?.cancel()
            hideControlsTask?.cancel()
            // Item replacement and temporary sheets are not a player exit.
            guard router.player?.id != presentation.id else { return }
            releasePlaybackIfNeeded()
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
        .task(id: item) {
            guard !Task.isCancelled, router.player?.id == presentation.id else { return }
            await controller.start(item) { ownedSession = $0 }
            guard !Task.isCancelled, router.player?.id == presentation.id else { return }
            ownedSession = controller.session
            scheduleControlsHide()
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
            failureKind: controller.failureKind,
            onRetry: {
                Task {
                    guard router.player?.id == presentation.id else { return }
                    await controller.start(item) { ownedSession = $0 }
                }
            },
            onClose: close,
            onPreviousChannel: hasChannelContext(item) && viewModel.canZap
                ? { Task { await viewModel.zap(by: -1) } }
                : nil,
            onNextChannel: hasChannelContext(item) && viewModel.canZap
                ? { Task { await viewModel.zap(by: 1) } }
                : nil
        )
    }

    func close() {
        hideControlsTask?.cancel()
        guard router.player?.id == presentation.id else { return }
        ownedSession = controller.session
        releasePlaybackIfNeeded()
        router.dismissPlayer(ifPresented: presentation.id)
    }

    func hasChannelContext(_ item: PlaybackItem) -> Bool {
        if case .liveChannel = item.source { return true }
        return false
    }

    private func releasePlaybackIfNeeded() {
        guard let session = ownedSession, controller.session == session else { return }
        if case .liveChannel = session.source,
           router.canReturnToLivePreview(from: presentation) {
            return
        }
        controller.stop(ifCurrent: session)
    }
}
