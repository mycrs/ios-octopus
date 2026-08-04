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
/// karar verir, `PlaybackEngine` protokolü üzerinden kontrol edilir.
/// AVPlayer'dan VLC'ye düşüş burada değil, `PlayerController`'da yönetilir.
/// Faz 5'te doldurulacak.
public struct PlayerScreen: View {

    private let dependencies: PlayerDependencies
    private let presentation: PlayerPresentation

    @EnvironmentObject private var router: AppRouter

    public init(presentation: PlayerPresentation, dependencies: PlayerDependencies) {
        self.presentation = presentation
        self.dependencies = dependencies
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            EmptyStateView(
                icon: "play.rectangle",
                title: "Oynatıcı",
                message: "Motor: \(dependencies.resolver.hasFallback ? "AVPlayer + VLC" : "yalnızca AVPlayer")\nFaz 5'te doldurulacak.",
                actionTitle: "Kapat",
                action: { router.dismissPlayer() }
            )
        }
    }
}
