import Foundation
import OctopusCore
import OctopusDomain
import OctopusData
import OctopusDesignSystem   // ThemeController
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
    private let validator: PlaylistValidating
    private let activation: ActivationRedeeming
    private let remoteConfig: RemoteConfigProviding

    // MARK: - Oynatma

    private let engineResolver: PlaybackEngineResolver

    /// Açılışta kalıcı depolama kurulamadıysa doldurulur.
    /// Uygulama çalışmaya devam eder ama veriler kalıcı olmaz.
    @Published private(set) var startupFailure: AppError?

    /// Panelden gelen yapılandırma (duyuru, bakım kapısı, marka).
    @Published private(set) var appConfig: RemoteAppConfig?

    /// Marka rengini yönetir; panel ve kullanıcı seçimi burada birleşir.
    let themeController = ThemeController()

    private var dismissedAnnouncementID: String? {
        get { UserDefaults.standard.string(forKey: "announcement.dismissed") }
        set { UserDefaults.standard.set(newValue, forKey: "announcement.dismissed") }
    }

    /// Kullanıcının henüz kapatmadığı duyuru.
    var visibleAnnouncement: Announcement? {
        guard let announcement = appConfig?.announcement else { return nil }
        return announcement.id == dismissedAnnouncementID ? nil : announcement
    }

    func dismissAnnouncement() {
        dismissedAnnouncementID = appConfig?.announcement?.id
        objectWillChange.send()
    }

    // MARK: - Kurulum

    /// - Parameter database: Testler için enjekte edilir. `nil` ise
    ///   diskteki kalıcı veritabanı açılır.
    init(database: AppDatabase? = nil) {
        let secretStore = KeychainSecretStore()
        secrets = secretStore

        if let database = database ?? Self.openDatabase() {
            let playlistRepository = GRDBPlaylistRepository(
                database: database,
                secrets: secretStore
            )
            let progressRepository = GRDBPlaybackProgressRepository(database: database)

            playlists = playlistRepository
            channels = GRDBChannelRepository(database: database)
            vod = GRDBVODRepository(database: database)
            series = GRDBSeriesRepository(database: database)
            epg = GRDBEPGRepository(database: database)
            favorites = GRDBFavoritesRepository(database: database)
            progress = progressRepository
            history = GRDBWatchHistoryRepository(database: database)

            // Kaynak türü dallanması yalnızca bu fabrikada olur.
            let providerFactory = DefaultContentProviderFactory(
                httpClient: URLSessionHTTPClient(),
                secrets: secretStore
            )
            streams = ProviderStreamResolver(
                playlists: playlistRepository,
                providerFactory: providerFactory,
                progress: progressRepository
            )
            sync = ContentSyncService(
                playlists: playlistRepository,
                providerFactory: providerFactory,
                database: database
            )
            // Doğrulama fabrikadan ayrı: kullanıcının az önce yazdığı parolayla
            // çalışır, parola henüz Keychain'de değildir.
            validator = ProviderValidator()
            activation = PanelActivationService()
            remoteConfig = PanelRemoteConfigService()

            startupFailure = nil
        } else {
            // Depolama hiç kurulamadı (disk dolu, izin sorunu…).
            // Çökmek yerine bellek içi depolarla açılır; kullanıcı uyarılır.
            Log.app.error("Depolama kurulamadı — oturumluk belleğe düşülüyor")
            playlists = InMemoryPlaylistRepository()
            channels = InMemoryChannelRepository()
            vod = InMemoryVODRepository()
            series = InMemorySeriesRepository()
            epg = InMemoryEPGRepository()
            favorites = InMemoryFavoritesRepository()
            progress = InMemoryPlaybackProgressRepository()
            history = InMemoryWatchHistoryRepository()
            // Depolama yokken senkronizasyonun yazacak yeri de yok.
            streams = ScaffoldStreamResolver()
            sync = ScaffoldContentSync()
            validator = ScaffoldValidator()
            // Panel servisleri depolamadan bağımsız çalışır; markalama ve
            // aktivasyon bu durumda da kullanılabilir olmalı.
            activation = PanelActivationService()
            remoteConfig = PanelRemoteConfigService()
            startupFailure = .storage(reason: "Veritabanı açılamadı")
        }

        // Motor zinciri: AVPlayer her zaman var, VLC yalnızca bağlıysa eklenir.
        // VLC yoksa uygulama AVPlayer'la çalışmaya devam eder — çökmez.
        engineResolver = PlaybackEngineResolver(
            native: { NullPlaybackEngine(identifier: "native") },  // 🚧 Faz 5: AVPlayerEngine()
            fallback: VLCEngineFactory.isAvailable ? { VLCEngineFactory.makeEngine() } : nil
        )

        Log.app.info("AppContainer hazır — yedek motor: \(VLCEngineFactory.isAvailable)")
    }

    /// Kalıcı veritabanını açar; olmazsa oturumluk belleğe düşer.
    ///
    /// Depolama sorunu uygulamayı çökertmemeli — kullanıcı en azından
    /// kaynağını girip yayın izleyebilmeli.
    private static func openDatabase() -> AppDatabase? {
        do {
            return try AppDatabase.makeShared()
        } catch {
            Log.app.error("Kalıcı veritabanı açılamadı: \(String(describing: error))")
            return try? AppDatabase.makeInMemory()
        }
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

        await refreshRemoteConfig()
    }

    /// Panel yapılandırmasını tazeler ve markayı uygular.
    ///
    /// Ağ hatası burada sessizdir: panel erişilemezse son bilinen
    /// yapılandırma kullanılır, uygulama açılmaya devam eder.
    func refreshRemoteConfig() async {
        let config = await remoteConfig.refresh()
        appConfig = config
        themeController.apply(branding: config?.branding)
    }

    // MARK: - Feature bağımlılıkları
    //
    // Her feature yalnızca ihtiyaç duyduğunu alır. `FeatureLive`'a
    // `PlaylistRepository` verilmez — göremediği şeyi yanlışlıkla kullanamaz.

    func makeOnboardingDependencies() -> OnboardingDependencies {
        OnboardingDependencies(
            playlists: playlists,
            validator: validator,
            activation: activation,
            sync: sync
        )
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
