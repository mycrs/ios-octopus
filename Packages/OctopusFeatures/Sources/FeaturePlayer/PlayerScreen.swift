import SwiftUI
import UIKit          // UIPasteboard
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

    public init(
        resolver: PlaybackEngineResolver,
        streams: StreamResolving,
        progress: PlaybackProgressRepository,
        history: WatchHistoryRepository,
        channels: ChannelRepository,
        vod: VODRepository,
        series: SeriesRepository
    ) {
        self.resolver = resolver
        self.streams = streams
        self.progress = progress
        self.history = history
        self.channels = channels
        self.vod = vod
        self.series = series
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

    @StateObject private var viewModel: PlayerViewModel
    @StateObject private var controller: PlayerController
    @EnvironmentObject private var router: AppRouter

    @State private var showsControls = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var isShowingTracks = false

    /// Denetimlerin kendiliğinden kaybolma süresi.
    private let autoHideDelay: Duration = .seconds(3.5)

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
        .task {
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

    private func controlsLayer(_ item: PlaybackItem) -> some View {
        ZStack {
            // Dokunma alanı tüm ekran: kullanıcı düğmeyi aramak zorunda kalmasın.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { toggleControls() }

            if showsControls {
                PlayerControlsOverlay(
                    title: item.title,
                    subtitle: item.subtitle,
                    isLive: item.isLive,
                    state: controller.state,
                    time: controller.time,
                    hasTracks: hasSelectableTracks,
                    onClose: close,
                    onTogglePlay: {
                        controller.togglePlayPause()
                        scheduleControlsHide()
                    },
                    onSkip: { delta in
                        Task { await controller.skip(by: delta) }
                        scheduleControlsHide()
                    },
                    onSeek: { position in
                        Task { await controller.seek(to: position) }
                        scheduleControlsHide()
                    },
                    onShowTracks: {
                        hideControlsTask?.cancel()
                        isShowingTracks = true
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showsControls)
    }

    private var hasSelectableTracks: Bool {
        controller.audioTracks.count > 1 || !controller.subtitleTracks.isEmpty
    }

    @ViewBuilder
    private var trackPicker: some View {
        PlayerTrackPicker(
            audioTracks: controller.audioTracks,
            subtitleTracks: controller.subtitleTracks,
            selectedAudio: controller.selectedAudioTrack,
            selectedSubtitle: controller.selectedSubtitleTrack,
            onSelect: controller.select
        )
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
    ///
    /// Adres kopyalanabilir bırakılıyor: harici bir oynatıcıda açılıyorsa
    /// sorun bizde, açılmıyorsa kaynakta. Bu ayrım destek için kritik.
    private func playbackFailure(_ error: AppError, item: PlaybackItem) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            EmptyStateView(
                icon: "play.slash",
                title: "Yayın açılamadı",
                message: error.userMessage,
                actionTitle: "Tekrar dene",
                action: { Task { await controller.start(item) } }
            )

            Text(PlayerViewModel.maskedURL(item.url))
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(Theme.Palette.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.md)

            HStack(spacing: Theme.Spacing.md) {
                Button {
                    UIPasteboard.general.string = item.url.absoluteString
                } label: {
                    Label("Adresi kopyala", systemImage: "doc.on.doc")
                }
                Button("Kapat", action: close)
                    .foregroundColor(Theme.Palette.textSecondary)
            }
            .font(Theme.Typography.caption)
        }
        .padding(Theme.Spacing.lg)
    }

    // MARK: - Denetim görünürlüğü

    private func toggleControls() {
        showsControls.toggle()
        if showsControls {
            scheduleControlsHide()
        } else {
            hideControlsTask?.cancel()
        }
    }

    /// Denetimleri belirli bir süre sonra gizler.
    ///
    /// ⚠️ Duraklatılmışken gizlenmez: ekranda hiçbir ipucu kalmaz ve
    /// kullanıcı videonun donduğunu sanır.
    private func scheduleControlsHide() {
        hideControlsTask?.cancel()
        showsControls = true

        hideControlsTask = Task {
            try? await Task.sleep(for: autoHideDelay)
            guard !Task.isCancelled, controller.state == .playing else { return }
            showsControls = false
        }
    }

    private func close() {
        hideControlsTask?.cancel()
        router.dismissPlayer()
    }
}
