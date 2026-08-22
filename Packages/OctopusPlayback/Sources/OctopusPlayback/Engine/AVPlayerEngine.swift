import Foundation
import AVFoundation
import AVKit
import UIKit
import OctopusCore
import OctopusDomain

/// AVFoundation tabanlı oynatma motoru — HLS ve MP4 için.
///
/// ## Neden bu motor önce denenir?
/// Sistem entegrasyonu VLC'de yok: PiP, AirPlay, kilit ekranı denetimleri,
/// donanım hızlandırmalı çözme (pil ömrü). Format desteklenmiyorsa
/// `PlaybackEngineResolver` VLC'ye yönlendirir.
///
/// ## Durum nereden geliyor?
/// Durum **AVPlayer'dan türetilir**, elle güdülmez. `timeControlStatus` +
/// `AVPlayerItem.status` birlikte okunur. Kendi bayraklarımızı tutup
/// "şimdi oynuyor olmalı" demek, ağ takıldığında gerçekle ayrışır ve
/// spinner hiç çıkmaz.
///
/// ⚠️ `teardown()` çağrılması **zorunlu**: IPTV panelleri eşzamanlı
/// bağlantı sayısını sınırlar. Bırakılmayan her akış kotadan bir hak yer
/// ve kullanıcı bir süre sonra `connectionLimitReached` görür.
@MainActor
public final class AVPlayerEngine: PlaybackEngine {

    public let identifier: String
    public let events: AsyncStream<PlaybackEvent>

    /// ⚠️ Bu bayrak "cihaz destekliyor mu" demek **değil**: simülatörde
    /// PiP yok ve kontrolör hiç kurulmaz. Düğmenin görünürlüğü
    /// `isPictureInPicturePossible` ile belirlenir (bkz. +PictureInPicture).
    public let supportsPictureInPicture = true

    /// AVPlayer sistem route'unu kullanır — video Apple TV'ye gider.
    public let supportsAirPlay = true

    public private(set) var currentState: PlaybackState = .idle
    public private(set) var audioTracks: [MediaTrack] = []
    public private(set) var subtitleTracks: [MediaTrack] = []

    // İz seçimi `AVPlayerEngine+Tracks.swift` içinde yönetilir; yazma
    // hakkı modül içinde, okuma dışarıda.
    public internal(set) var selectedAudioTrack: MediaTrack?
    public internal(set) var selectedSubtitleTrack: MediaTrack?

    let player: AVPlayer
    /// `MediaTrack.id` → AVFoundation seçeneği. `select(track:)` bunu kullanır.
    var trackOptions: [String: AVMediaSelectionOption] = [:]
    /// Türe göre medya seçim grubu — seçim yapmak için grup şart.
    var mediaGroups: [MediaTrack.Kind: AVMediaSelectionGroup] = [:]

    private let continuation: AsyncStream<PlaybackEvent>.Continuation
    private let audioSession: AudioSessionController
    /// Kullanıcı tercihleri; verilmezse varsayılan davranış sürer.
    private let preferences: PlaybackPreferences?

    private var observations: [NSKeyValueObservation] = []
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var trackDiscovery: Task<Void, Never>?

    private var isLiveContent = false
    private var didReachEnd = false

    /// Bu içerikten hiç görüntü karesi geldi mi?
    ///
    /// ⚠️ "Açıldı" ile "görüntü var" aynı şey **değil**. HEVC/UHD yayınlarda
    /// AVPlayer sesi çözer, videoyu çözemez ve `status` yine `readyToPlay`
    /// kalır — hata hiç düşmez. Bu bayrak olmadan kullanıcı siyah ekranda
    /// ses dinler, yedek motor da hiç devreye girmez.
    private var didRenderVideo = false

    /// Görüntüsüz oynatmayı yakalayan gözcü.
    private var videoWatchdog: Task<Void, Never>?
    private var videoFit: VideoFit = .fit
    /// Motorun **tek** çizim yüzeyi.
    ///
    /// ⚠️ Güçlü tutuluyor ve her istekte yenisi üretilmiyor: aynı
    /// `AVPlayer`'a ikinci bir `AVPlayerLayer` bağlamak güvenilir değil —
    /// AVFoundation tek katmana çizer, diğeri siyah kalır. Mini oynatıcı
    /// ile tam ekran arasında geçerken yüzey **taşınıyor** (bkz.
    /// `VLCPlaybackEngine.surface` üzerindeki ayrıntılı not).
    /// Ömrü `releaseCurrentItem()`/`teardown()` ile biter.
    private var layerView: PlayerLayerView?
    /// AVKit'e bağımlı tek parça — `AVPlayerEngine+PictureInPicture.swift`.
    var pictureInPictureController: AVPictureInPictureController?

    /// Kullanıcının seçtiği oynatma hızı.
    ///
    /// ⚠️ `player.play()` hızı **her zaman 1.0'a döndürür**. 1.5x seçip
    /// duraklatıp devam eden kullanıcı normal hıza düşerdi; bu yüzden
    /// `play()` doğrudan `rate` atar.
    private var preferredRate: Float = 1.0

    /// - Parameter audioSession: Testlerde sahte oturum verilebilsin diye
    ///   dışarıdan alınır.
    ///
    /// ⚠️ Varsayılan değer **imzada değil, gövdede** üretiliyor:
    /// `AudioSessionController` `@MainActor` izole ve varsayılan parametre
    /// ifadeleri izolasyonsuz bağlamda değerlendirilir — imzaya yazılınca
    /// "call to main actor-isolated initializer in a synchronous
    /// nonisolated context" hatası veriyordu.
    public init(
        identifier: String = "avplayer",
        audioSession: AudioSessionController? = nil,
        preferences: PlaybackPreferences? = nil
    ) {
        self.identifier = identifier
        self.audioSession = audioSession ?? AudioSessionController()
        self.preferences = preferences
        self.player = AVPlayer()

        var capturedContinuation: AsyncStream<PlaybackEvent>.Continuation!
        self.events = AsyncStream { capturedContinuation = $0 }
        self.continuation = capturedContinuation

        // Gerçek değer içeriğe göre `load()`'da belirleniyor (canlı ≠ VOD).
        observeInterruptions()
    }

    // MARK: - Yükleme

    public func load(_ item: PlaybackItem) async {
        releaseCurrentItem()

        // ⚠️ Önceki içeriğin iz keşfi **iptal edilmeli**. Edilmezse kanal
        // değiştikten sonra tamamlanıp eski yayının ses/altyazı izlerini
        // yayınlıyor; iz seçici yanlış listeyi gösteriyordu.
        trackDiscovery?.cancel()

        didReachEnd = false
        didRenderVideo = false
        isLiveContent = item.isLive
        audioTracks = []
        subtitleTracks = []
        trackOptions = [:]
        mediaGroups = [:]
        selectedAudioTrack = nil
        selectedSubtitleTrack = nil
        transition(to: .loading)

        let asset = Self.makeAsset(for: item)
        let playerItem = AVPlayerItem(asset: asset)

        // ⚠️ KANAL GEÇİŞ HIZI: canlıda tampon beklemek her zapta gecikmedir.
        // "Hızlı"da hiç beklenmez (kopma riski karşılığında), "Kararlı"da
        // AVPlayer kendi tamponunu doldurur. VOD'da her zaman beklenir —
        // orada akıcılık gecikmeden önemli.
        let buffer = preferences?.liveBuffer ?? .balanced
        player.automaticallyWaitsToMinimizeStalling = !item.isLive || buffer == .stable

        // Canlıda hedef tampon: seçilen süre. AVPlayer bunu bir **öneri**
        // olarak alır, garanti değildir.
        if item.isLive {
            playerItem.preferredForwardBufferDuration = buffer.seconds
        }

        player.replaceCurrentItem(with: playerItem)

        audioSession.activate()
        observe(playerItem)

        // ⚠️ İz keşfi **beklenmez**: asset'in medya seçim gruplarını
        // çözmesi ağ gecikmesi kadar sürebilir. Beklenirse ekran o süre
        // boyunca "yükleniyor"da kalır, oysa video çoktan çizilebilir.
        trackDiscovery = Task { [weak self] in
            await self?.discoverTracks(in: asset)
        }

        if let resumeAt = item.resumeAt, resumeAt > 0 {
            await seek(to: resumeAt)
        }

        Log.playback.info("AVPlayer yükledi: \(item.format.rawValue, privacy: .public)")
    }

    /// Asset'i istek başlıklarıyla birlikte kurar.
    ///
    /// ⚠️ IPTV'de başlıklar isteğe bağlı değil: panellerin çoğu
    /// `User-Agent` kontrol eder ve beklenmedik değerde **403** döner.
    ///
    /// `AVURLAssetHTTPHeaderFieldsKey` Apple tarafından belgelenmemiş bir
    /// anahtardır (belgelenmiş alternatifi yok; `AVAssetResourceLoaderDelegate`
    /// ile elle indirmek HLS'te pratik değil). Yaygın kullanımda ve
    /// App Store'da kabul görüyor. Başlık yoksa anahtar hiç yazılmaz —
    /// gereksiz yere özel API yüzeyine dokunulmasın.
    static func makeAsset(for item: PlaybackItem) -> AVURLAsset {
        AVURLAsset(url: item.url, options: assetOptions(for: item))
    }

    /// Seçenek sözlüğü ayrı: `AVURLAsset` kendisine verilen options'ı geri
    /// okutmaz, bu yüzden başlıkların doğru kurulduğu ancak burada test edilebilir.
    static func assetOptions(for item: PlaybackItem) -> [String: Any] {
        guard !item.headers.isEmpty else { return [:] }
        return ["AVURLAssetHTTPHeaderFieldsKey": item.headers]
    }

    // MARK: - Denetimler

    public func play() {
        // `play()` değil `rate` — seçili hız korunsun (bkz. preferredRate).
        player.rate = preferredRate
    }

    public func pause() {
        player.pause()
    }

    public func stop() {
        player.pause()
        releaseCurrentItem()
        player.replaceCurrentItem(with: nil)
        transition(to: .idle)
    }

    public func seek(to seconds: TimeInterval) async {
        // Canlı yayında konum kavramı yok; istek sessizce yok sayılır.
        guard !isLiveContent, player.currentItem != nil else { return }

        let target = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        // Tolerans sıfır: kullanıcı çubuğu bıraktığı yere gitmeli, en
        // yakın anahtar kareye değil. Maliyeti biraz daha uzun arama.
        _ = await player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)

        // Sonuna kadar sarılıp geri gelindiğinde "bitti" durumu kalkmalı.
        didReachEnd = false
        syncPlaybackState()
    }

    public func setVolume(_ volume: Float) {
        player.volume = min(max(volume, 0), 1)
    }

    public func setRate(_ rate: Float) {
        preferredRate = max(0.5, min(rate, 2.0))
        // Duraklamışken hız atamak oynatmayı başlatırdı — sadece çalarken uygula.
        if player.timeControlStatus != .paused {
            player.rate = preferredRate
        }
    }

    public func makeVideoView() -> UIView {
        // Yüzey zaten varsa **aynısı** döner; çağıran onu kendi taşıyıcısına
        // ekleyince görünüm taşınır. İkinci bir katman üretmek yerine
        // taşımak, ekranlar arası geçişte siyah kalmayı önler.
        if let layerView {
            layerView.videoGravity = Self.gravity(for: videoFit)
            return layerView
        }

        let view = PlayerLayerView()
        view.player = player
        view.videoGravity = Self.gravity(for: videoFit)
        layerView = view
        // PiP bir **katmana** bağlıdır; katman her yenilendiğinde kontrolör
        // de yenilenmeli, yoksa ölü bir katmanı işaret eder.
        attachPictureInPicture(to: view)
        return view
    }

    public func setVideoFit(_ fit: VideoFit) {
        videoFit = fit
        layerView?.videoGravity = Self.gravity(for: fit)
    }

    private static func gravity(for fit: VideoFit) -> AVLayerVideoGravity {
        fit == .fill ? .resizeAspectFill : .resizeAspect
    }

    public func teardown() {
        // Kullanıcı oynatıcıyı kapattıysa etkin küçük pencere de kapanır.
        // Geri hareketi PiP'e dönüşmemeli ve oynatma arkada sürmemeli.
        pictureInPictureController?.stopPictureInPicture()
        pictureInPictureController = nil
        trackDiscovery?.cancel()
        trackDiscovery = nil
        releaseCurrentItem()
        player.replaceCurrentItem(with: nil)
        // Yüzey güçlü tutulduğu için burada bırakılmalı, yoksa motor
        // bırakıldıktan sonra da katman bellekte kalır.
        layerView?.removeFromSuperview()
        layerView = nil
        audioSession.stopObserving()
        audioSession.deactivate()
        continuation.finish()
        Log.playback.info("AVPlayer bırakıldı")
    }

    // MARK: - Gözlem

    private func observe(_ playerItem: AVPlayerItem) {
        // ⚠️ Gözlem gövdelerinde **hiçbir değer taşınmıyor**: yalnızca
        // "bir şey değişti" sinyali ana aktöre atlıyor, güncel değeri
        // metodun kendisi okuyor. Değer taşımak Sendable ihlali üretirdi.
        observations = [
            playerItem.observe(\.status, options: [.new, .initial]) { [weak self] _, _ in
                Task { @MainActor in self?.syncItemStatus() }
            },
            playerItem.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.syncPlaybackState() }
            },
            playerItem.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.syncPlaybackState() }
            },
            playerItem.observe(\.presentationSize, options: [.new, .initial]) { [weak self] _, _ in
                Task { @MainActor in self?.reportNaturalSize() }
            },
            player.observe(\.timeControlStatus, options: [.new, .initial]) { [weak self] _, _ in
                Task { @MainActor in self?.syncPlaybackState() }
            }
        ]

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleReachedEnd() }
        }

        // Yarım saniye: ilerleme çubuğu akıcı görünsün ama gereksiz
        // uyandırma olmasın. Kaydetme sıklığı ayrı (PlayerController, ~5 sn).
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reportTime() }
        }
    }

    private func releaseCurrentItem() {
        videoWatchdog?.cancel()
        videoWatchdog = nil

        observations.forEach { $0.invalidate() }
        observations = []

        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
    }

    private func observeInterruptions() {
        audioSession.observeInterruptions { [weak self] interruption in
            guard let self else { return }
            switch interruption {
            case .began:
                // iOS zaten duraklattı; durum gözlemden gelecek.
                break
            case .endedShouldResume:
                self.play()
            case .endedShouldStay:
                break
            }
        }
    }

    // MARK: - Durum türetme

    private func syncItemStatus() {
        guard let playerItem = player.currentItem else { return }

        switch playerItem.status {
        case .failed:
            fail(with: Self.classify(playerItem))
        case .readyToPlay:
            syncPlaybackState()
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    /// Tek doğruluk kaynağı: AVPlayer ne diyorsa o.
    private func syncPlaybackState() {
        if case .failed = currentState { return }
        if didReachEnd { return }

        guard let playerItem = player.currentItem else {
            transition(to: .idle)
            return
        }

        guard playerItem.status == .readyToPlay else {
            transition(to: .loading)
            return
        }

        switch player.timeControlStatus {
        case .playing:
            transition(to: .playing)
        case .paused:
            transition(to: .paused)
        case .waitingToPlayAtSpecifiedRate:
            // Ağ yetişemiyor: tampon dolana kadar spinner.
            transition(to: .buffering)
        @unknown default:
            break
        }
    }

    /// Açılamama sebebini kullanıcının anlayacağı bir hataya çevirir.
    ///
    /// ⚠️ IPTV'de bu ayrım çok önemli: `AVFoundation`'ın kendi metni
    /// ("The operation could not be completed") kullanıcıya hiçbir şey
    /// söylemez. Oysa sebep neredeyse her zaman üç şeyden biridir:
    /// abonelik bitmiş, aynı anda çok fazla cihaz bağlı, ya da yayın
    /// gerçekten kapanmış. HTTP durum kodu bunları ayırt etmeye yeter.
    ///
    /// Durum kodu `errorLog()` üzerinden okunur — `AVPlayerItem.error`
    /// HTTP katmanını taşımaz.
    nonisolated static func classify(_ playerItem: AVPlayerItem) -> AppError {
        let statusCode = playerItem.errorLog()?.events.last?.errorStatusCode ?? 0

        switch statusCode {
        case 401:
            return .unauthorized

        case 403:
            // ⚠️ 403 tek başına `unauthorized` sayılmıyor: o hata
            // "kaynağı yeniden yapılandır" demek (`requiresReauthentication`)
            // ve kullanıcıyı gereksizce kurulum ekranına yollardı. Panellerin
            // çoğu bağlantı sınırında da 403 döner — sebep belirsiz, mesaj
            // ikisini birden anlatmalı.
            return .playbackFailed(reason:
                "Sunucu erişimi reddetti (403). Aboneliğin süresi dolmuş ya da "
                + "aynı anda izin verilen cihaz sayısı aşılmış olabilir."
            )

        case 404, 410:
            return .playbackFailed(reason: "Yayın sunucuda bulunamadı. Kaynağı güncellemeyi dene.")

        case 500...599:
            return .network(reason: "Sunucu şu an yanıt veremiyor (\(statusCode)).")

        default:
            let detail = playerItem.error?.localizedDescription
            // Durum kodu yoksa sorun genelde ağın kendisidir (DNS, zaman aşımı).
            return .playbackFailed(reason: detail ?? "Yayın açılamadı (bilinmeyen sebep).")
        }
    }

    private func handleReachedEnd() {
        // Canlı yayında "bitti" gelirse bu bir kopmadır, son değil —
        // kullanıcıya "yayın bitti" demek yanıltıcı olur.
        guard !isLiveContent else {
            fail(with: .playbackFailed(reason: "Canlı yayın kesildi"))
            return
        }
        didReachEnd = true
        transition(to: .ended)
    }

    private func fail(with error: AppError) {
        transition(to: .failed(error))
        // Koordinatör bunu görünce yedek motoru (VLC) dener.
        continuation.yield(.unrecoverableFailure(error))
    }

    private func transition(to state: PlaybackState) {
        guard state != currentState else { return }
        currentState = state
        continuation.yield(.stateChanged(state))

        if state == .playing { startVideoWatchdogIfNeeded() }
    }

    // MARK: - Görüntüsüz oynatma gözcüsü

    /// Ses çalıyor ama görüntü hiç gelmiyorsa bunu **başarısızlık** sayar.
    ///
    /// ## Neden gerekli?
    /// AVPlayer, çözemediği bir video izini sessizce atlar: `status`
    /// `readyToPlay` kalır, `error` boştur, ses akmaya devam eder.
    /// HEVC/UHD IPTV kanallarında tipik sonuç budur. Hata düşmediği için
    /// `PlayerController` yedek motoru hiç denemez ve kullanıcı siyah
    /// ekranda ses dinler — bildirilen hata tam olarak buydu.
    ///
    /// ⚠️ Yalnızca **oynatma gerçekten başladıktan** sonra sayılır:
    /// tamponlama sırasında görüntü boyutu zaten `.zero`'dur ve erken
    /// karar açılmakta olan yayınları boşuna yedeğe yollardı.
    private func startVideoWatchdogIfNeeded() {
        guard !didRenderVideo, videoWatchdog == nil else { return }

        videoWatchdog = Task { [weak self] in
            // Karar süresi: **oynatma başladıktan** sonra sayılıyor, yani
            // ses çoktan akıyor. O noktada 3 saniye boyunca hiç kare
            // gelmediyse video izi çözülmüyor demektir. Daha uzun beklemek
            // (önceki hâli 5 sn) zaplarken kullanıcıyı siyah ekranda tutuyor.
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            // `Task` ana aktör bağlamını miras alır — `await` gerekmiyor.
            self?.failIfStillBlind()
        }
    }

    /// Gözcünün kararı. Ayrı metot: `Task` gövdesinden izole çağrı gerekiyor.
    private func failIfStillBlind() {
        videoWatchdog = nil

        guard !didRenderVideo, case .playing = currentState else { return }

        // ⚠️ Sesli yayınlar (radyo kanalları) da boyutsuzdur ve buraya
        // düşer. Yedek motor onları sorunsuz açtığı için zarar yok;
        // "video izi var mı" sorusunu HLS'te AVFoundation zaten
        // cevaplamıyor, o yüzden ayrım yapılamıyor.
        Log.playback.notice("Ses var, görüntü yok — yedek motora yönlendiriliyor")

        fail(with: .playbackFailed(reason:
            "Görüntü çözülemedi (muhtemelen HEVC/H.265). Yedek oynatıcı deneniyor."
        ))
    }

    /// Asset'te video izi yoksa siyah ekran hata değildir; bu bir ses/radyo akışıdır.
    func markAudioOnlyPlayback() {
        didRenderVideo = true
        videoWatchdog?.cancel()
        videoWatchdog = nil
    }

    // MARK: - Zaman ve boyut

    private func reportTime() {
        guard let playerItem = player.currentItem else { return }

        let current = playerItem.currentTime().seconds
        guard current.isFinite else { return }

        // Canlıda süre `indefinite` gelir (NaN). `nil` = "ilerleme çubuğu çizme".
        let rawDuration = playerItem.duration.seconds
        let duration: TimeInterval? = (isLiveContent || !rawDuration.isFinite || rawDuration <= 0)
            ? nil
            : rawDuration

        let buffered = playerItem.loadedTimeRanges
            .map { CMTimeGetSeconds($0.timeRangeValue.end) }
            .filter { $0.isFinite }
            .max() ?? current

        continuation.yield(.timeChanged(
            PlaybackTime(current: current, duration: duration, bufferedUpTo: buffered)
        ))
    }

    private func reportNaturalSize() {
        guard let size = player.currentItem?.presentationSize,
              size.width > 0, size.height > 0
        else { return }

        // Görüntü geldi: gözcünün işi bitti.
        didRenderVideo = true
        videoWatchdog?.cancel()
        videoWatchdog = nil

        continuation.yield(.naturalSizeChanged(
            width: Double(size.width),
            height: Double(size.height)
        ))
    }

    // MARK: - İzler (AVPlayerEngine+Tracks.swift)

    func publish(audio: [MediaTrack], subtitle: [MediaTrack]) {
        audioTracks = audio
        subtitleTracks = subtitle
        continuation.yield(.tracksDiscovered(audio: audio, subtitle: subtitle))
    }
}
