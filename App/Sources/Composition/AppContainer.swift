import Foundation
import OctopusCore
import OctopusDomain
import OctopusData
import OctopusNavigation
import OctopusPlayback
import OctopusPlaybackVLC
import FeatureOnboarding
import FeatureHome
import FeatureLive
import FeatureVOD
import FeatureSeries
import FeatureSearch
import FeaturePlayer
import FeatureSettings

/// 🔌 COMPOSITION ROOT — somut tiplerin birleştiği **tek** yer.
///
/// Uygulamanın tamamında `XtreamContentProvider`, `GRDBChannelRepository` gibi
/// somut sınıfların adı yalnızca bu dosyada geçer. Feature'lar protokol görür.
///
/// Bu dosya büyüdüğünde bile sadece `let x = XImpl(...)` satırları çoğalır —
/// mantık barındırmaz. `OctopusApp.swift` bu sayede 40 satırda kalır.
@MainActor
final class AppContainer: ObservableObject {

    // MARK: - Gezinme

    let router = AppRouter()

    // MARK: - Altyapı

    private let secrets: SecretStore

    // MARK: - Depolar (hepsi PROTOKOL tipinde — somut tip dışarı sızmaz)

    private let playlists: PlaylistRepository
    private let channels: ChannelRepository
    private let vod: VODRepository
    private let series: SeriesRepository
    private let epg: EPGRepository
    private let favorites: FavoritesRepository
    private let progress: PlaybackProgressRepository
    private let history: WatchHistoryRepository
    private let streams: StreamResolving
    private let sync: ContentSyncing

    // MARK: - Oynatma

    private let engineResolver: PlaybackEngineResolver

    // MARK: - Kurulum

    init() {
        secrets = KeychainSecretStore()

        // 🚧 Faz 1-2: aşağıdaki satırlar GRDB destekli implementasyonlarla değişecek.
        // Değişecek tek yer burasıdır — hiçbir ekran etkilenmez.
        playlists = InMemoryPlaylistRepository()
        channels = InMemoryChannelRepository()
        vod = InMemoryVODRepository()
        series = InMemorySeriesRepository()
        epg = InMemoryEPGRepository()
        favorites = InMemoryFavoritesRepository()
        progress = InMemoryPlaybackProgressRepository()
        history = InMemoryWatchHistoryRepository()
        streams = ScaffoldStreamResolver()
        sync = ScaffoldContentSync()

        // Motor zinciri: AVPlayer her zaman var, VLC yalnızca bağlıysa eklenir.
        // VLC yoksa uygulama AVPlayer'la çalışmaya devam eder — çökmez.
        engineResolver = PlaybackEngineResolver(
            native: { NullPlaybackEngine(identifier: "native") },  // 🚧 Faz 5: AVPlayerEngine()
            fallback: VLCEngineFactory.isAvailable ? { VLCEngineFactory.makeEngine() } : nil
        )

        Log.app.info("AppContainer hazır — yedek motor: \(VLCEngineFactory.isAvailable)")
    }

    /// Açılışta kaynak var mı? Yoksa onboarding gösterilir.
    func bootstrap() async {
        do {
            let active = try await playlists.activePlaylist()
            router.needsOnboarding = (active == nil)
        } catch {
            Log.app.error("Açılış kontrolü başarısız: \(String(describing: error))")
            router.needsOnboarding = true
        }
    }

    // MARK: - Feature bağımlılıkları
    //
    // Her feature yalnızca ihtiyaç duyduğunu alır. `FeatureLive`'a
    // `PlaylistRepository` verilmez — göremediği şeyi yanlışlıkla kullanamaz.

    func makeOnboardingDependencies() -> OnboardingDependencies {
        OnboardingDependencies(playlists: playlists, sync: sync)
    }

    func makeHomeDependencies() -> HomeDependencies {
        HomeDependencies(
            playlists: playlists,
            channels: channels,
            vod: vod,
            series: series,
            progress: progress,
            history: history
        )
    }

    func makeLiveDependencies() -> LiveDependencies {
        LiveDependencies(channels: channels, epg: epg, favorites: favorites)
    }

    func makeVODDependencies() -> VODDependencies {
        VODDependencies(vod: vod, favorites: favorites, progress: progress)
    }

    func makeSeriesDependencies() -> SeriesDependencies {
        SeriesDependencies(series: series, favorites: favorites, progress: progress)
    }

    func makeSearchDependencies() -> SearchDependencies {
        SearchDependencies(channels: channels, vod: vod, series: series)
    }

    func makePlayerDependencies() -> PlayerDependencies {
        PlayerDependencies(
            resolver: engineResolver,
            streams: streams,
            progress: progress,
            history: history,
            channels: channels,
            vod: vod,
            series: series
        )
    }

    func makeSettingsDependencies() -> SettingsDependencies {
        SettingsDependencies(
            playlists: playlists,
            sync: sync,
            progress: progress,
            history: history
        )
    }
}
