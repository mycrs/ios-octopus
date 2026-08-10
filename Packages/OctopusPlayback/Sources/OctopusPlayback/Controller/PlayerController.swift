import Foundation
import Combine
import UIKit
import OctopusCore
import OctopusDomain

/// Motorun üstündeki koordinatör: yaşam döngüsü, yedeğe düşme, ilerleme.
///
/// ## Neden motorun kendisi yetmiyor?
/// Motor tek bir işi bilir: verilen adresi açmak. Üç şey onun işi değil:
/// 1. **Hangi motor?** — açamazsa VLC ile yeniden denemek,
/// 2. **Nerede kalmıştı?** — devam konumunu okuyup yazmak,
/// 3. **SwiftUI'a nasıl anlatılır?** — `AsyncStream` → `@Published`.
///
/// Bunlar motora konsaydı her yeni motor aynı mantığı baştan yazardı.
///
/// ⚠️ `finish()` çağrılması **zorunlu**: hem IPTV bağlantı kotası hem de
/// son izleme konumunun kaydı buna bağlı.
@MainActor
public final class PlayerController: ObservableObject {

    // MARK: - Yayınlanan durum

    @Published public private(set) var state: PlaybackState = .idle
    @Published public private(set) var time: PlaybackTime = .zero
    @Published public private(set) var audioTracks: [MediaTrack] = []
    @Published public private(set) var subtitleTracks: [MediaTrack] = []
    @Published public private(set) var selectedAudioTrack: MediaTrack?
    @Published public private(set) var selectedSubtitleTrack: MediaTrack?

    /// Videonun en/boy oranı — siyah bantları doğru hesaplamak için.
    @Published public private(set) var aspectRatio: Double?

    /// Hangi motor çalışıyor? (Loglama ve hata ayıklama için.)
    @Published public private(set) var engineIdentifier: String = ""

    /// Video yüzeyinin kimliği — SwiftUI tarafı bunu `.id()` olarak kullanır.
    ///
    /// ⚠️ `engineIdentifier` bu iş için **yetmez**: her `attach` yeni bir
    /// motor **örneği** üretir ama kimlik dizgesi aynı kalabilir
    /// (AVPlayer → AVPlayer, kanal değiştirirken olan tam olarak budur).
    /// Kimlik değişmeyince SwiftUI yüzeyi yeniden kurmaz ve ekranda
    /// bırakılmış eski motorun katmanı kalır — kanal değişir, ses gelir,
    /// görüntü donar. Sayaç her motorda artar, bu yüzden güvenli.
    @Published public private(set) var surfaceGeneration = 0

    /// Çalışan motor AirPlay destekliyor mu? Düğmenin görünürlüğü buna bağlı.
    @Published public private(set) var supportsAirPlay = false

    /// PiP **şu an** başlatılabilir mi?
    ///
    /// ⚠️ Zamanla değişir: video yüklenene kadar `false`. Bu yüzden
    /// durum her değiştiğinde motora yeniden soruluyor — bir kez okuyup
    /// saklamak, düğmenin hiç çıkmamasına yol açardı.
    @Published public private(set) var canUsePictureInPicture = false

    /// Kullanıcının seçtiği oynatma hızı (canlıda kullanılmaz).
    @Published public private(set) var rate: Float = 1.0

    /// Görüntünün çerçeveye yerleşimi.
    ///
    /// ⚠️ Motor değişse bile korunur: kullanıcı 4:3 bir yayında ekranı
    /// doldurmayı seçtiyse, yedeğe düşüldüğünde tercihi kaybolmamalı.
    @Published public private(set) var videoFit: VideoFit = .fit

    // MARK: - Bağımlılıklar

    private let resolver: PlaybackEngineResolver
    private let progress: PlaybackProgressRepository
    private let history: WatchHistoryRepository
    /// Kullanıcı tercihleri; verilmezse varsayılan davranış sürer.
    private let preferences: PlaybackPreferences?
    private let nowPlaying: NowPlayingCenter
    private let saveInterval: TimeInterval
    private let liveStallTimeout: Duration
    private let vodStallTimeout: Duration
    private let now: () -> Date

    /// Ekranın kendiliğinden kararmasını engeller.
    ///
    /// ⚠️ Video izlerken **zorunlu**: iOS varsayılan olarak birkaç dakika
    /// sonra ekranı kapatır ve kullanıcı filmin ortasında karanlığa bakar.
    /// Kapanış olarak alınıyor ki testler `UIApplication`'a dokunmasın.
    private let setScreenAwake: @MainActor (Bool) -> Void

    // MARK: - İç durum

    private var engine: PlaybackEngine?
    private var eventTask: Task<Void, Never>?
    /// Gecikmeli fallback/yeniden bağlanma işi ekran kapandıktan sonra dirilmemeli.
    private var recoveryTask: Task<Void, Never>?
    /// Motor hata vermeden yüklemede kalırsa kurtarma zincirini başlatır.
    private var stallTask: Task<Void, Never>?
    private var item: PlaybackItem?
    private var decision: PlaybackEngineResolver.Decision = .native
    /// Her açma/kapatma işlemi önceki asenkron yüklemeleri geçersiz kılar.
    private var sessionGeneration = 0

    /// Yedek motora **yalnızca bir kez** düşülür; iki motor da açamıyorsa
    /// hata kullanıcıya gösterilir. Aksi hâlde sonsuz döngü riski var.
    private var didAttemptFallback = false

    /// Kopan canlı yayına kaç kez yeniden bağlanmayı denedik?
    /// Oynatma gerçekten başladığında sıfırlanır.
    private var reconnectAttempts = 0

    /// Kullanıcı otomatik yeniden bağlanmayı kapattıysa hiç denenmez.
    private var maxReconnectAttempts: Int {
        (preferences?.autoReconnect ?? true) ? 3 : 0
    }

    /// Açılış ölçümünün başladığı an.
    ///
    /// Kanal geçiş hızı "hızlı/yavaş" diye tartışılamaz; ölçülür. İlk kare
    /// geldiğinde geçen süre loglanır, böylece yavaşlığın motorda mı,
    /// yedeğe düşmede mi, yoksa sunucuda mı olduğu ayrılabilir.
    private var openStartedAt: Date?

    private var lastSavedAt: Date?
    private var didRecordHistory = false

    /// ⚠️ `nowPlaying` varsayılanı **gövdede** üretiliyor: `@MainActor`
    /// izole bir tipin örneği varsayılan parametre ifadesi olamaz
    /// (bkz. `AVPlayerEngine.init`, aynı tuzak CI'da yakalandı).
    public init(
        resolver: PlaybackEngineResolver,
        progress: PlaybackProgressRepository,
        history: WatchHistoryRepository,
        preferences: PlaybackPreferences? = nil,
        nowPlaying: NowPlayingCenter? = nil,
        saveInterval: TimeInterval = 5,
        liveStallTimeout: Duration = .seconds(20),
        vodStallTimeout: Duration = .seconds(45),
        now: @escaping () -> Date = Date.init,
        // Varsayılan bir **kapanış**; `UIApplication.shared`'a ancak
        // çağrıldığında dokunur. Bu yüzden izolasyon tuzağına düşmez.
        setScreenAwake: @escaping @MainActor (Bool) -> Void = { keepAwake in
            UIApplication.shared.isIdleTimerDisabled = keepAwake
        }
    ) {
        self.resolver = resolver
        self.progress = progress
        self.history = history
        self.preferences = preferences
        // Kullanıcının son seçtiği yerleşimle başla — her yayında yeniden
        // "ekranı doldur" demek zorunda kalmasın.
        self.videoFit = preferences?.videoFit ?? .fit
        self.nowPlaying = nowPlaying ?? NowPlayingCenter()
        self.saveInterval = saveInterval
        self.liveStallTimeout = liveStallTimeout
        self.vodStallTimeout = vodStallTimeout
        self.now = now
        self.setScreenAwake = setScreenAwake
    }

    // MARK: - Yaşam döngüsü

    /// İçeriği açar. Devam konumu burada eklenir.
    public func start(_ requested: PlaybackItem) async {
        sessionGeneration &+= 1
        let session = sessionGeneration
        recoveryTask?.cancel()
        recoveryTask = nil
        stallTask?.cancel()
        stallTask = nil
        didAttemptFallback = false
        didRecordHistory = false
        reconnectAttempts = 0
        lastSavedAt = nil
        openStartedAt = now()
        rate = 1.0
        videoFit = preferences?.videoFit ?? videoFit
        clearMediaMetadata()
        state = .loading

        let prepared = await withResumePosition(requested)
        guard !Task.isCancelled, sessionGeneration == session else { return }
        item = prepared
        let allowsFallback = preferences?.useFallbackEngine ?? true
        let wanted = resolver.decide(
            for: prepared.format,
            allowingFallback: allowsFallback
        )

        attachRemoteCommands(isLive: prepared.isLive)

        // ⚠️ KANAL GEÇİŞ HIZI: aynı motor zaten çalışıyorsa **yeniden
        // kurulmuyor**, yalnızca yeni içerik yükleniyor.
        //
        // Her geçişte yeni motor üretmek şunları da beraberinde getiriyordu:
        // eski motorun `teardown`'ı (VLC'de `stop()` ana iş parçacığını
        // tıkar), yeni `AVPlayer`, ses oturumunun yeniden etkinleştirilmesi,
        // PiP kontrolörünün yeniden kurulması ve `surfaceGeneration`
        // arttığı için SwiftUI'ın video yüzeyini baştan yaratması.
        // Zaplarken hepsi her kanalda tekrarlanıyordu.
        if let engine, wanted == decision {
            await reload(prepared, on: engine, session: session)
            return
        }

        decision = wanted
        await attach(
            resolver.makeEngine(
                for: prepared.format,
                allowingFallback: allowsFallback
            ),
            loading: prepared,
            session: session
        )
    }

    /// Çalışan motora yeni içerik yükler.
    ///
    /// Motor korunuyor ama **içeriğe ait yayınlanmış durum sıfırlanmalı**:
    /// aksi hâlde yeni kanalda bir önceki yayının izleri, süresi ve
    /// en-boy oranı ekranda asılı kalır.
    private func reload(
        _ target: PlaybackItem,
        on engine: PlaybackEngine,
        session: Int
    ) async {
        clearMediaMetadata()
        engine.setVideoFit(videoFit)
        engine.setRate(rate)

        await engine.load(target)
        // `load` beklerken ekran kapanmış ya da başka içerik başlamış olabilir.
        guard
            sessionGeneration == session,
            self.engine === engine,
            item?.url == target.url
        else { return }
        engine.play()
    }

    /// Kilit ekranı düğmelerini bu oturuma bağlar.
    private func attachRemoteCommands(isLive: Bool) {
        nowPlaying.attach(
            handlers: NowPlayingCenter.Handlers(
                play: { [weak self] in self?.play() },
                pause: { [weak self] in self?.pause() },
                toggle: { [weak self] in
                    Task { await self?.togglePlayPause() }
                },
                skip: { [weak self] delta in
                    Task { await self?.skip(by: delta) }
                },
                seek: { [weak self] position in
                    Task { await self?.seek(to: position) }
                }
            ),
            isLive: isLive
        )
    }

    /// Kaydedilmiş konumu içeriğe iliştirir.
    ///
    /// ⚠️ Bitmiş (%95+) içerik baştan başlar: kullanıcı filmi tekrar
    /// açtığında son saniyesine atlamak istemez.
    private func withResumePosition(_ item: PlaybackItem) async -> PlaybackItem {
        guard !item.isLive, item.resumeAt == nil else { return item }

        guard
            let saved = try? await progress.progress(for: item.source),
            !saved.isFinished,
            saved.positionSeconds > 1
        else { return item }

        return item.resuming(at: saved.positionSeconds)
    }

    private func attach(
        _ newEngine: PlaybackEngine,
        loading target: PlaybackItem,
        session: Int
    ) async {
        eventTask?.cancel()
        engine?.teardown()
        clearMediaMetadata()

        engine = newEngine
        engineIdentifier = newEngine.identifier
        surfaceGeneration += 1
        supportsAirPlay = newEngine.supportsAirPlay
        canUsePictureInPicture = false
        // Yerleşim tercihi kullanıcıya ait, motora değil — yeni motora taşınır.
        newEngine.setVideoFit(videoFit)
        // VOD hızı da fallback sırasında korunur. Yeni içerikte `start()` zaten 1x'e çeker.
        newEngine.setRate(rate)

        // ⚠️ Abonelik yüklemeden **önce** kurulur. Ters sırada, yükleme
        // sırasında düşen olaylar (ör. anında gelen hata) kaybolurdu:
        // `AsyncStream` dinleyicisi yokken yayınlanan değer yok olur
        // (bkz. BRAIN.md § 11.1 — aynı tuzak testlerde yaşandı).
        eventTask = Task { [weak self] in
            for await event in newEngine.events {
                guard !Task.isCancelled else { break }
                self?.handle(event)
            }
        }

        await newEngine.load(target)
        // Async yükleme sırasında `finish()` motoru bırakmış olabilir; kapanmış
        // ekranda `play()` çağırıp bağlantıyı yeniden diriltme.
        guard
            sessionGeneration == session,
            engine === newEngine,
            item?.url == target.url
        else { return }
        newEngine.play()
    }

    /// Ekran kapanırken çağrılır. **Atlanamaz.**
    public func finish() async {
        sessionGeneration &+= 1
        recoveryTask?.cancel()
        recoveryTask = nil
        stallTask?.cancel()
        stallTask = nil
        await saveProgress(force: true)

        eventTask?.cancel()
        eventTask = nil
        engine?.teardown()
        engine = nil
        item = nil
        // Atlanırsa kilit ekranında çalmayan bir içerik asılı kalır.
        nowPlaying.clear()
        // ⚠️ Atlanırsa ekran **uygulama boyunca** hiç kararmaz: bayrak
        // süreç genelindedir, oynatıcıya ait değil.
        setScreenAwake(false)
        clearMediaMetadata()
        supportsAirPlay = false
        engineIdentifier = ""
        rate = 1.0
        state = .idle
    }

    // MARK: - Denetimler

    public func play() {
        engine?.play()
    }

    public func pause() {
        engine?.pause()
        // Duraklatma bilinçli bir andır: konumu hemen yaz, uygulama
        // arka planda öldürülse bile kayıp olmasın.
        Task { await saveProgress(force: true) }
    }

    public func togglePlayPause() async {
        if state == .ended, let item, !item.isLive {
            // Biten VOD'da `play()` tek başına hiçbir şey yapmaz; medya son
            // karede kalır. Açıkça sıfırdan yeniden yüklenir.
            await start(item.resuming(at: 0))
            return
        }

        if state == .playing {
            pause()
        } else {
            play()
        }
    }

    public func seek(to seconds: TimeInterval) async {
        await engine?.seek(to: seconds)
        // Aramadan sonra kilit ekranı gerçek konumu göstermeli.
        refreshNowPlaying()
    }

    /// İleri/geri sarma. Sınırlar burada uygulanır ki her düğme
    /// aynı davranışı paylaşsın.
    public func skip(by delta: TimeInterval) async {
        guard let duration = time.duration else { return }
        let target = min(max(time.current + delta, 0), duration)
        await seek(to: target)
    }

    public func select(track: MediaTrack) {
        engine?.select(track: track)
        selectedAudioTrack = engine?.selectedAudioTrack
        selectedSubtitleTrack = engine?.selectedSubtitleTrack
    }

    public func setRate(_ newRate: Float) {
        let clamped = max(0.5, min(newRate, 2.0))
        engine?.setRate(clamped)
        rate = clamped
        refreshNowPlaying()
    }

    /// Konumu hemen yazar — arka plana geçerken çağrılır.
    ///
    /// Normal akışta konum ~5 sn'de bir kaydediliyor; uygulama arka planda
    /// öldürülürse aradaki fark kaybolur. Bu, "şimdi yaz" için son
    /// güvenilir an.
    public func persistPosition() async {
        await saveProgress(force: true)
    }

    /// PiP'i başlatır. Kullanıcı küçük pencereyi kendisi kapatır.
    public func startPictureInPicture() {
        engine?.setPictureInPictureActive(true)
    }

    public func toggleVideoFit() {
        videoFit = videoFit.toggled
        // Seçim kalıcı: bir sonraki yayında da aynı yerleşimle açılsın.
        preferences?.videoFit = videoFit
        engine?.setVideoFit(videoFit)
    }

    /// Video yüzeyi. Motor yoksa `nil` — çağıran siyah zemin gösterir.
    public func makeVideoView() -> UIView? {
        engine?.makeVideoView()
    }

    // MARK: - Olaylar

    private func handle(_ event: PlaybackEvent) {
        switch event {
        case .stateChanged(let newState):
            state = newState
            updateStallWatchdog(for: newState)
            if newState == .playing {
                reportOpenDuration()
                recordHistoryOnce()
                // ⚠️ Sıfırlama şart: saatlerce izlenen bir kanalda arada
                // yaşanan kopmalar birikip hakkı tüketirdi. Sayaç
                // "art arda başarısız deneme" sayar, "toplam kopma" değil.
                reconnectAttempts = 0
            }
            // Yalnızca gerçekten oynarken: duraklatılmış bir videonun
            // başında uyuyakalan kullanıcının pili bitmemeli.
            setScreenAwake(newState == .playing)
            canUsePictureInPicture = engine?.isPictureInPicturePossible ?? false
            refreshNowPlaying()

        case .timeChanged(let newTime):
            let learnedDuration = time.duration == nil && newTime.duration != nil
            time = newTime
            // ⚠️ Kilit ekranı her yarım saniyede tazelenmez: sistem konumu
            // `playbackRate` üzerinden kendi ilerletir. Yalnızca süre ilk
            // kez öğrenildiğinde yazmak yeterli — sık yazmak çubuğu titretir.
            if learnedDuration { refreshNowPlaying() }
            Task { await saveProgress(force: false) }

        case .tracksDiscovered(let audio, let subtitle):
            audioTracks = audio
            subtitleTracks = subtitle
            selectedAudioTrack = engine?.selectedAudioTrack
            selectedSubtitleTrack = engine?.selectedSubtitleTrack

        case .naturalSizeChanged(let width, let height):
            aspectRatio = height > 0 ? width / height : nil

        case .unrecoverableFailure(let error):
            stallTask?.cancel()
            stallTask = nil
            recoveryTask?.cancel()
            recoveryTask = Task { [weak self] in
                await self?.handleFailure(error)
            }
        }
    }

    /// Önce yedek motoru dene, o da yoksa canlı yayında yeniden bağlan.
    private func handleFailure(_ error: AppError) async {
        let session = sessionGeneration
        guard !Task.isCancelled else { return }

        if
            !didAttemptFallback,
            // Kullanıcı yedek motoru kapattıysa hiç denenmez — teşhis için
            // bilinçli bir seçim (bkz. `PlaybackPreferences.useFallbackEngine`).
            preferences?.useFallbackEngine ?? true,
            resolver.canRetryWithFallback(after: decision),
            let fallback = resolver.makeRuntimeFallbackEngine(),
            let target = item
        {
            didAttemptFallback = true
            decision = .fallback
            Log.playback.notice("Native motor açamadı, yedeğe geçiliyor: \(String(describing: error))")

            // Kaldığı yer korunur: kullanıcı motor değiştiğini fark etmemeli.
            let resumed = target.resuming(at: time.current > 1 ? time.current : target.resumeAt)
            guard !Task.isCancelled, sessionGeneration == session else { return }
            await attach(fallback, loading: resumed, session: session)
            return
        }

        if await reconnectIfLive() { return }
        guard !Task.isCancelled else { return }

        state = .failed(error)
        setScreenAwake(false)
        refreshNowPlaying()
    }

    /// Kopan canlı yayına sessizce yeniden bağlanır.
    ///
    /// ## Neden gerekli?
    /// IPTV'de anlık kopma olağan: sunucu segmenti geciktirir, bağlantı
    /// düşer, kanal bir an kapanır. Kullanıcıya hemen hata ekranı gösterip
    /// "Tekrar dene" düğmesine bastırmak, elle yapılabilecek bir işi ona
    /// yıkmak olur — kopmaların çoğu birkaç saniyede kendiliğinden düzelir.
    ///
    /// ⚠️ Yalnızca **canlı** yayında: VOD'da kopma genelde kalıcı bir
    /// sebeptendir (dosya yok, abonelik bitti) ve sessizce tekrar denemek
    /// sorunu gizler.
    ///
    /// ⚠️ Deneme sayısı sınırlı ve gecikme artıyor: ölü bir kanalda sonsuz
    /// döngüye girip sunucuyu dövmemek için.
    private func reconnectIfLive() async -> Bool {
        let session = sessionGeneration
        guard
            let target = item, target.isLive,
            reconnectAttempts < maxReconnectAttempts,
            engine != nil
        else {
            Log.playback.error("Oynatma başarısız, yeniden bağlanılamadı")
            return false
        }

        reconnectAttempts += 1
        let attempt = reconnectAttempts

        // Hata ekranı yerine spinner: kullanıcı için bu bir kesinti değil,
        // tamponlama gibi görünmeli.
        state = .buffering
        Log.playback.notice("Canlı yayın koptu, yeniden bağlanılıyor (\(attempt))")

        try? await Task.sleep(for: .seconds(2 * attempt))

        // Bekleme sırasında ekran kapanmış ya da kanal değişmiş olabilir.
        guard
            !Task.isCancelled,
            sessionGeneration == session,
            let engine,
            let current = item, current.url == target.url
        else { return true }

        await reload(current, on: engine, session: session)
        return true
    }

    /// Hata yayınlamadan yüklemede kalan motoru kurtarır.
    ///
    /// Bazı bozuk IPTV uçları bağlantıyı açık tutup hiç segment göndermez;
    /// AVPlayer/VLC bu durumda sonsuza kadar spinner'da kalabilir. Canlıda
    /// kısa, VOD'da yanlış pozitif üretmemek için daha uzun eşik kullanılır.
    private func updateStallWatchdog(for newState: PlaybackState) {
        stallTask?.cancel()
        stallTask = nil

        guard newState.showsSpinner, let target = item else { return }
        let timeout = target.isLive ? liveStallTimeout : vodStallTimeout

        stallTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard
                !Task.isCancelled,
                let self,
                self.item?.url == target.url,
                self.state.showsSpinner
            else { return }

            self.stallTask = nil
            self.recoveryTask?.cancel()
            self.recoveryTask = Task { [weak self] in
                await self?.handleFailure(.playbackFailed(
                    reason: target.isLive
                        ? "Canlı yayın uzun süre yanıt vermedi."
                        : "Video uzun süre yüklenemedi."
                ))
            }
        }
    }

    private func clearMediaMetadata() {
        audioTracks = []
        subtitleTracks = []
        selectedAudioTrack = nil
        selectedSubtitleTrack = nil
        aspectRatio = nil
        time = .zero
        canUsePictureInPicture = false
    }

    /// İlk kareye kadar geçen süreyi bir kez yazar.
    ///
    /// Hangi motorun açtığı da yazılıyor: yedeğe düşülen kanallarda süre
    /// doğal olarak uzundur (önce native denenir), bu ayrım olmadan sayı
    /// yanıltıcı olur.
    private func reportOpenDuration() {
        guard let openStartedAt else { return }
        self.openStartedAt = nil

        let elapsed = Int(now().timeIntervalSince(openStartedAt) * 1000)
        Log.playback.notice(
            "Açılış: \(elapsed) ms · motor \(self.engineIdentifier, privacy: .public)"
        )
    }

    private func refreshNowPlaying() {
        guard let item else { return }
        nowPlaying.update(
            item: item,
            time: time,
            isPlaying: state == .playing,
            rate: rate
        )
    }

    private func recordHistoryOnce() {
        guard !didRecordHistory, let source = item?.source else { return }
        didRecordHistory = true

        // ⚠️ Kayıt anı: **gerçekten oynamaya başladığında**. Adres
        // çözüldüğünde kaydetmek, açılmayan yayınları da "izlendi"
        // sayardı ve "kaldığın kanal" kartı yanlış kanalı gösterirdi.
        let recordedAt = now()
        Task { [history] in
            try? await history.record(source, at: recordedAt)
        }
    }

    // MARK: - İlerleme kaydı

    /// Konumu kaydeder. `force` değilse aralık dolmadan yazmaz.
    ///
    /// ⚠️ Canlı yayında kayıt yok: konumun anlamı olmadığı gibi, "devam et"
    /// rafına canlı kanal düşmesi de yanlış olurdu.
    private func saveProgress(force: Bool) async {
        guard
            let item, !item.isLive,
            let duration = time.duration, duration > 0,
            time.current > 0
        else { return }

        let timestamp = now()
        if !force, let lastSavedAt, timestamp.timeIntervalSince(lastSavedAt) < saveInterval {
            return
        }
        lastSavedAt = timestamp

        let snapshot = PlaybackProgress(
            itemKey: item.source.storageKey,
            positionSeconds: time.current,
            durationSeconds: duration,
            updatedAt: timestamp
        )

        // Hata yutulur: ilerleme kaydı oynatmayı bölmemeli.
        try? await progress.save(snapshot, for: item.source)
    }
}
