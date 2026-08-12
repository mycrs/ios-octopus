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
import FeatureFavorites
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
    /// Bayi kodu karşılığı markalama ve sunucu listesi.
    private let resellerConfig: ResellerConfigProviding
    /// Ebeveyn kilidi depolamadan bağımsız çalışır (Keychain).
    private let parental: ParentalControlling
    /// Hızlı kurulumla korunan listenin, +18 kilidinden ayrı erişim kapısı.
    private let playlistAccess: PlaylistAccessControlling

    /// Yalnızca CI ekran görüntüsü tohumlaması için saklanır.
    /// Depolar protokol arkasında; bu referans onların yerine geçmez.
    private let seedableDatabase: AppDatabase?

    // MARK: - Oynatma

    private let engineResolver: PlaybackEngineResolver

    /// Açılışta kalıcı depolama kurulamadıysa doldurulur.
    /// Uygulama çalışmaya devam eder ama veriler kalıcı olmaz.
    @Published private(set) var startupFailure: AppError?

    /// Panelden gelen yapılandırma (duyuru, bakım kapısı, marka).
    @Published private(set) var appConfig: RemoteAppConfig?

    /// Marka rengini yönetir; panel ve kullanıcı seçimi burada birleşir.
    let themeController = ThemeController()

    /// Uygulama dili: cihaz tercihi veya Ayarlar'daki açık kullanıcı seçimi.
    let languageController = LanguageController()

    /// İçerik erişimi değiştiğinde sekme köklerini yeniden kurar. Böylece
    /// daha önce yüklenmiş listelerde korumalı bir kart görünür kalmaz.
    @Published private(set) var contentProtectionRevision = 0
    @Published private(set) var isActivePlaylistLocked = false
    @Published private(set) var activePlaylistName: String?

    /// Oynatma tercihleri — hem Ayarlar ekranı düzenler, hem motorlar okur.
    /// Tek örnek olmalı: iki kopya olsaydı ayarı değiştirmek oynatıcıya
    /// ulaşmazdı (`ThemeController` ile aynı gerekçe).
    let playbackPreferences = PlaybackPreferences()

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

    func contentProtectionDidChange() {
        contentProtectionRevision &+= 1
        router.clearOpenScreens()
    }

    /// Uygulama görünürlüğünü kaybedince geçici erişim sona erer.
    func lockProtectedContent() async {
        await parental.lock()
        await playlistAccess.lockAll()
        await refreshActivePlaylistAccess()
        if isActivePlaylistLocked {
            // Korumalı liste arka planda PiP veya açık detay üzerinden görünür kalmamalı.
            router.clearOpenScreens()
        }
        // Tam ekran oynatıcı dışarıdaki PiP oturumunu yönetir; burada onu
        // koşulsuz kapatmak normal içerikte PiP'i bozardı. Sekme kökleri
        // yeniden kurulur, oynatıcı da kendi kaynağını ayrıca doğrular.
        contentProtectionRevision &+= 1
    }

    // MARK: - Kurulum

    /// - Parameter database: Testler için enjekte edilir. `nil` ise
    ///   diskteki kalıcı veritabanı açılır.
    init(database: AppDatabase? = nil) {
        // Görsel boru hattı depolardan önce kurulur: ilk ekran açılmadan
        // hazır olmalı, sonradan değiştirmek yarım kalan indirmeleri iptal eder.
        ImageLoading.configure()

        let secretStore = KeychainSecretStore()
        secrets = secretStore
        parental = KeychainParentalControl(secrets: secretStore)
        playlistAccess = KeychainPlaylistAccessControl(secrets: secretStore)

        let openedDatabase = database ?? Self.openDatabase()
        seedableDatabase = openedDatabase

        if let database = openedDatabase {
            let playlistRepository = GRDBPlaylistRepository(
                database: database,
                secrets: secretStore
            )
            let progressRepository = GRDBPlaybackProgressRepository(database: database)

            // Kaynak türü dallanması yalnızca bu fabrikada olur.
            // Dizi deposu ağaç yüklemek için buna ihtiyaç duyduğundan
            // depolardan önce kurulur.
            let providerFactory = DefaultContentProviderFactory(
                httpClient: URLSessionHTTPClient(),
                secrets: secretStore,
                // Sağlayıcılar sunucu adresini sık değiştiriyor; kayıtlı
                // adres ölünce panelin yedek listesine geçilir.
                hostResolver: DNSFailoverService()
            )

            playlists = playlistRepository
            channels = GRDBChannelRepository(database: database)
            vod = GRDBVODRepository(
                database: database,
                detailLoader: ProviderMovieDetailLoader(
                    playlists: playlistRepository,
                    providerFactory: providerFactory
                )
            )
            series = GRDBSeriesRepository(
                database: database,
                // Sezon/bölüm ağacı ayrı bir istektir; depo yerel veriden
                // sorumlu, bu yükleyici uzak veriden.
                detailLoader: ProviderSeriesDetailLoader(
                    playlists: playlistRepository,
                    providerFactory: providerFactory
                )
            )
            epg = GRDBEPGRepository(database: database)
            favorites = GRDBFavoritesRepository(database: database)
            progress = progressRepository
            history = GRDBWatchHistoryRepository(database: database)
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

        // Bayi yapılandırması depolamadan bağımsız: kullanıcı kodu
        // girdiyse marka ve sunucu listesi her koşulda gelmeli.
        resellerConfig = PanelResellerConfigService()

        // Motor zinciri: AVPlayer her zaman var, yedek motor bağlıysa eklenir.
        // Hiçbiri yoksa uygulama AVPlayer'la çalışmaya devam eder — çökmez.
        // Motorlar tercihleri **kendileri** okur (tampon süresi gibi
        // değerler `load()` anında geçerli olmalı, kurulum anında değil).
        let preferences = playbackPreferences
        engineResolver = PlaybackEngineResolver(
            native: { AVPlayerEngine(preferences: preferences) },
            fallback: Self.makeFallbackEngineFactory(preferences: preferences)
        )

        Log.app.info("AppContainer hazır — yedek motor: \(Self.fallbackEngineName, privacy: .public)")
    }

    // MARK: - Yedek oynatma motoru

    /// Yedek motor fabrikası.
    ///
    /// ⚠️ Bir dönem üçüncü motor (KSPlayer/FFmpeg) da bağlıydı ve **tek
    /// satırla** seçilebiliyordu; UHD yayınlarında kütüphanenin kendi iz
    /// ayrıştırması deterministik olarak çöktüğü için kaldırıldı
    /// (bkz. `Docs/BRAIN.md`). Bırakılan ders: yeni bir motor eklemek
    /// yalnızca burayı ve yeni modülü ilgilendirir — resolver, controller
    /// ve ekranlar değişmez.
    private static func makeFallbackEngineFactory(
        preferences: PlaybackPreferences
    ) -> PlaybackEngineResolver.EngineFactory? {
        guard VLCEngineFactory.isAvailable else { return nil }
        return { VLCEngineFactory.makeEngine(preferences: preferences) }
    }

    private static var fallbackEngineName: String {
        VLCEngineFactory.isAvailable ? "VLC" : "yok"
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
        await seedDemoDataIfRequested()

        do {
            let active = try await playlists.activePlaylist()
            router.needsOnboarding = (active == nil)
            await refreshActivePlaylistAccess(active: active)

            #if DEBUG
            // CI görsel denetimi: hızlı kurulumdan PIN ile gelen gerçek liste
            // kapısının uygulama açılışında katalogdan önce durduğunu gösterir.
            if ProcessInfo.processInfo.arguments.contains("-startupPlaylistLock"),
               let active {
                try? await playlistAccess.configure(active.id, pin: "4821")
                await playlistAccess.lockAll()
                await refreshActivePlaylistAccess(active: active)
            }
            #endif
        } catch {
            Log.app.error("Açılış kontrolü başarısız: \(String(describing: error))")
            router.needsOnboarding = true
            isActivePlaylistLocked = false
            activePlaylistName = nil
        }

        await refreshRemoteConfig()

        #if DEBUG
        // CI görsel denetimi: panelin kırmızı marka rengi seçtiği durumu
        // gerçek tema zincirinden geçirir; üretim yapılandırmasını etkilemez.
        if ProcessInfo.processInfo.arguments.contains("-startupRedBrand") {
            themeController.apply(
                branding: BrandConfiguration(
                    primaryColorHex: "#FF3B30",
                    resellerName: "Nova Play",
                    logoURL: nil
                )
            )
        }

        // Açılışta doğrudan oynatıcıyı açar. Onboarding gösteriliyorsa
        // atlanır — oynatacak kaynak yok.
        if !router.needsOnboarding {
            if ProcessInfo.processInfo.arguments.contains("-startupSettings") {
                router.switchTab(to: .home, then: .about)
            } else if ProcessInfo.processInfo.arguments.contains("-startupSearch") {
                router.switchTab(to: .home, then: .search)
            } else if DemoCatalogSeeder.isPlayerRequested {
                // Tek parça bayrak: Xcode'un argüman listesinde boşluklu
                // satır tek argüman sayıldığı için elle kurulumda
                // `-startup.player <key>` biçimi çalışmıyordu.
                router.presentPlayer(DemoCatalogSeeder.firstChannelSource)
            } else {
                router.openStartupPlayerIfRequested()
            }
        }
        #endif
    }

    /// CI ekran görüntüsü modu: sahte katalog yazılır.
    ///
    /// Tasarım kör yapılmasın diye — kaynak eklenmemiş bir uygulamada
    /// yalnızca karşılama ekranı kare alınabiliyordu.
    private func seedDemoDataIfRequested() async {
        #if DEBUG
        guard DemoCatalogSeeder.isRequested, let database = seedableDatabase else { return }
        do {
            try await DemoCatalogSeeder.seed(into: database, secrets: secrets)
        } catch {
            Log.app.error("Demo katalog tohumlanamadı: \(String(describing: error))")
        }
        #endif
    }

    /// Panel yapılandırmasını tazeler ve markayı uygular.
    ///
    /// Ağ hatası burada sessizdir: panel erişilemezse son bilinen
    /// yapılandırma kullanılır, uygulama açılmaya devam eder.
    func refreshRemoteConfig() async {
        let global = await remoteConfig.refresh()

        // ⚠️ Sıra önemli: bayi yapılandırması globalin **üzerine** uygulanır.
        // Bayi kendi rengini seçtiyse global tema onu ezmemeli.
        let merged = await applyingResellerConfig(to: global)

        appConfig = merged
        themeController.apply(branding: merged?.branding)
    }

    /// Kayıtlı bayi kodu varsa yapılandırmasını çeker ve birleştirir.
    ///
    /// Kod yoksa hiç ağa çıkılmaz — kod girmemiş kullanıcıda her açılışta
    /// boşuna bir istek atmak hem gecikme hem de panel yükü demek.
    private func applyingResellerConfig(to global: RemoteAppConfig?) async -> RemoteAppConfig? {
        guard let code = await resellerConfig.savedCode() else { return global }

        // Ağ yoksa önbellekteki bayi yapılandırması kullanılır: bayinin
        // müşterisi çevrimdışıyken markasız bir uygulama görmemeli.
        //
        // ⚠️ `??` ile tek satırda yazılamıyor: operatörün sağ tarafı bir
        // autoclosure ve içinde `await` bulunamaz
        // ("'async' call in an autoclosure that does not support concurrency"
        // — BRAIN.md § 11.1'deki XCTAssert tuzağının aynısı).
        let fetched = await resellerConfig.fetch(code: code)
        let fallback = fetched == nil ? await resellerConfig.cached() : nil
        guard let reseller = fetched ?? fallback else { return global }

        // Global yapılandırma hiç gelmediyse bile bayi bilgisi tek başına
        // anlamlıdır (marka, kapı, duyuru).
        let base = global ?? RemoteAppConfig(fetchedAt: Date())
        return base.applying(reseller)
    }

    /// Kullanıcının girdiği bayi kodunu kaydeder ve yapılandırmayı tazeler.
    ///
    /// - Returns: Kod panelde bulunduysa `true`.
    @discardableResult
    func applyResellerCode(_ code: String?) async -> Bool {
        // Kod siliniyorsa: kaydı temizle, markayı globale geri döndür.
        guard let code, ResellerConfig.normalizeCode(code) != nil else {
            await resellerConfig.save(code: nil)
            await refreshRemoteConfig()
            return true
        }

        await resellerConfig.save(code: code)
        let fetched = await resellerConfig.fetch(code: code)

        // Kod tutmadıysa kaydı geri al — yanlış kod kalıcı olmamalı.
        if fetched == nil {
            await resellerConfig.save(code: nil)
        }

        await refreshRemoteConfig()
        return fetched != nil
    }

    /// Kayıtlı bayi kodu (Ayarlar ekranı gösterir).
    func savedResellerCode() async -> String? {
        await resellerConfig.savedCode()
    }

    /// Bayinin sunucu listesi — kaynak eklerken adres yazdırmamak için.
    func resellerServers() async -> [ResellerServer] {
        let cached = await resellerConfig.cached()
        return cached?.servers ?? []
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
            sync: sync,
            activatePlaylist: { [weak self] id, pin in
                guard let self else { return }
                try await self.activatePlaylist(id, setupPIN: pin)
            },
            // Panel elle girişi kapattıysa yalnızca aktivasyon kodu sunulur.
            // Yapılandırma henüz gelmediyse açık kabul edilir — kullanıcıyı
            // kaynak ekleyemez hâlde bırakmak en kötü seçenek.
            isManualLoginEnabled: { [weak self] in
                self?.appConfig?.isXtreamLoginEnabled ?? true
            },
            // Aktivasyon kodundan gelen bayi markasını uygula.
            onBrandingResolved: { [weak self] branding in
                self?.themeController.apply(branding: branding)
            },
            // Bayi kodu: markayı ve sunucu listesini getirir.
            applyResellerCode: { [weak self] code in
                await self?.applyResellerCode(code) ?? false
            },
            savedResellerCode: { [weak self] in
                await self?.savedResellerCode()
            },
            resellerServers: { [weak self] in
                await self?.resellerServers() ?? []
            },
            // Bayi markası: panelden gelen ad ve logo karşılamada görünür.
            brandName: { [weak self] in self?.appConfig?.branding.resellerName },
            brandLogoURL: { [weak self] in self?.appConfig?.branding.logoURL }
        )
    }

    func makeHomeDependencies() -> HomeDependencies {
        HomeDependencies(
            playlists: playlists,
            channels: channels,
            vod: vod,
            series: series,
            progress: progress,
            history: history,
            sync: sync,
            parental: parental
        )
    }

    func makeLiveDependencies() -> LiveDependencies {
        LiveDependencies(
            playlists: playlists,
            channels: channels,
            epg: epg,
            favorites: favorites,
            history: history,
            // Gömülü mini oynatıcı için — tam ekran oynatıcıyla **aynı**
            // resolver ve akış çözücü kullanılır ki motor seçimi ve
            // 403/kimlik davranışı iki yerde ayrışmasın.
            resolver: engineResolver,
            streams: streams,
            progress: progress,
            preferences: playbackPreferences,
            parental: parental
        )
    }

    func makeVODDependencies() -> VODDependencies {
        VODDependencies(
            playlists: playlists,
            vod: vod,
            favorites: favorites,
            progress: progress,
            parental: parental
        )
    }

    func makeSeriesDependencies() -> SeriesDependencies {
        SeriesDependencies(
            playlists: playlists,
            series: series,
            favorites: favorites,
            progress: progress,
            parental: parental
        )
    }

    func makeFavoritesDependencies() -> FavoritesDependencies {
        FavoritesDependencies(
            playlists: playlists,
            favorites: favorites,
            parental: parental
        )
    }

    func makeSearchDependencies() -> SearchDependencies {
        SearchDependencies(
            playlists: playlists,
            channels: channels,
            vod: vod,
            series: series,
            parental: parental
        )
    }

    func makePlayerDependencies() -> PlayerDependencies {
        PlayerDependencies(
            resolver: engineResolver,
            streams: streams,
            progress: progress,
            history: history,
            channels: channels,
            vod: vod,
            series: series,
            epg: epg,
            preferences: playbackPreferences,
            // Zaplama listesi de süzülmeli — yoksa kilit oynatıcıdan atlatılır.
            parental: parental
        )
    }

    func makeSettingsDependencies() -> SettingsDependencies {
        SettingsDependencies(
            playlists: playlists,
            sync: sync,
            progress: progress,
            history: history,
            // Destek kanalları panelden gelir; henüz çekilmediyse boş.
            contact: appConfig?.contact ?? .empty,
            parental: parental,
            channels: channels,
            vod: vod,
            series: series,
            playlistAccess: playlistAccess,
            activatePlaylist: { [weak self] id, pin in
                guard let self else { return false }
                return try await self.activatePlaylist(id, enteredPIN: pin)
            },
            removePlaylistLock: { [weak self] id in
                await self?.playlistAccess.remove(id)
            },
            notifyPlaylistChanged: { [weak self] in
                await self?.refreshActivePlaylistAccess()
            },
            notifyProtectionChanged: { [weak self] in
                self?.contentProtectionDidChange()
            }
        )
    }

    // MARK: - Hızlı kurulum liste kilidi

    func unlockActivePlaylist(with pin: String) async -> Bool {
        guard let active = try? await playlists.activePlaylist() else {
            return false
        }
        let didUnlock = await playlistAccess.unlock(active.id, with: pin)
        await refreshActivePlaylistAccess(active: active)
        return didUnlock
    }

    private func activatePlaylist(_ id: Playlist.ID, setupPIN: String?) async throws {
        if let setupPIN {
            try await playlistAccess.configure(id, pin: setupPIN)
        } else {
            await playlistAccess.remove(id)
        }
        do {
            try await playlists.setActive(id: id)
        } catch {
            await playlistAccess.remove(id)
            throw error
        }
        await refreshActivePlaylistAccess()
    }

    private func activatePlaylist(_ id: Playlist.ID, enteredPIN: String?) async throws -> Bool {
        if await playlistAccess.isProtected(id), !(await playlistAccess.isUnlocked(id)) {
            guard let enteredPIN,
                  await playlistAccess.unlock(id, with: enteredPIN)
            else { return false }
        }
        try await playlists.setActive(id: id)
        await refreshActivePlaylistAccess()
        return true
    }

    private func refreshActivePlaylistAccess(active supplied: Playlist? = nil) async {
        let active: Playlist?
        if let supplied {
            active = supplied
        } else {
            active = try? await playlists.activePlaylist()
        }
        activePlaylistName = active?.name
        guard let active else {
            isActivePlaylistLocked = false
            return
        }
        isActivePlaylistLocked = await playlistAccess.isProtected(active.id)
            && !(await playlistAccess.isUnlocked(active.id))
    }
}
