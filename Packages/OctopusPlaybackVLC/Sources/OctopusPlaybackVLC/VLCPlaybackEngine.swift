import Foundation
import UIKit
import VLCKitSPM
import OctopusCore
import OctopusDomain
import OctopusPlayback

/// VLCKit tabanlı oynatma motoru — MPEG-TS, MKV, AVI, RTSP, RTMP için.
///
/// ## Neden bu motor gerekli?
/// AVPlayer yalnızca HLS ve MP4 açar. IPTV panellerinin canlı yayınları
/// ham MPEG-TS, filmleri çoğu zaman MKV'dir. AVPlayer bunları alınca
/// **sesi çözüp videoyu çözemez** — kullanıcı siyah ekranda ses duyar.
/// Belirti tam olarak buydu; çözüm bu motordur.
///
/// ## Durum nereden geliyor?
/// `AVPlayerEngine` durumu AVPlayer'dan türetir; burada da aynı kural:
/// tek doğruluk kaynağı `VLCMediaPlayer.state`. Kendi bayrağımızı tutup
/// "şimdi oynuyor olmalı" demek, ağ takıldığında gerçekle ayrışır.
///
/// ## AVPlayer'da olup burada olmayanlar
/// - **PiP yok**: `AVPictureInPictureController` bir `AVPlayerLayer`'a
///   bağlanır; VLC kendi kareleri çizer, ortada katman yoktur.
/// - **AirPlay yok**: sistem route'u kullanılmadığı için Apple TV'ye
///   yalnızca ses giderdi. Düğmeyi göstermek çalışmayan özellik vaat etmek olur.
///
/// ⚠️ `teardown()` çağrılması **zorunlu**: IPTV panelleri eşzamanlı
/// bağlantıyı sınırlar; bırakılmayan her akış kotadan bir hak yer.
@MainActor
public final class VLCPlaybackEngine: NSObject, PlaybackEngine {

    public let identifier: String
    public let events: AsyncStream<PlaybackEvent>

    /// VLC kendi karelerini çizer — sistem katmanı yok, PiP kurulamaz.
    public let supportsPictureInPicture = false
    public var isPictureInPicturePossible: Bool { false }
    public func setPictureInPictureActive(_ active: Bool) {}

    /// Sistem route'u kullanılmıyor; AirPlay'de yalnızca ses giderdi.
    public let supportsAirPlay = false

    public private(set) var currentState: PlaybackState = .idle
    public private(set) var audioTracks: [MediaTrack] = []
    public private(set) var subtitleTracks: [MediaTrack] = []
    // İz seçimi `VLCPlaybackEngine+Tracks.swift` içinde yönetiliyor;
    // `private(set)` yazma hakkını **aynı dosyaya** kısıtlar, bu yüzden
    // modül içi (`AVPlayerEngine` ile aynı desen).
    public internal(set) var selectedAudioTrack: MediaTrack?
    public internal(set) var selectedSubtitleTrack: MediaTrack?

    let player: VLCMediaPlayer

    /// `MediaTrack.id` → VLC iz indeksi. VLC izleri `Int32` ile seçer.
    var trackIndexes: [String: Int32] = [:]

    private let continuation: AsyncStream<PlaybackEvent>.Continuation
    private let audioSession: AudioSessionController
    /// Kullanıcı tercihleri; verilmezse varsayılan davranış sürer.
    private let preferences: PlaybackPreferences?

    private var isLiveContent = false
    private var didPublishTracks = false

    /// Açılış gözcüsü.
    ///
    /// ⚠️ VLC **hata vermeden sonsuza kadar bekleyebilir**: sunucu yanıt
    /// vermezse durum `.opening`'de takılır, `.error` hiç gelmez ve
    /// kullanıcı dönen bir spinner'a bakar. AVPlayer'ın kendi zaman aşımı
    /// var, VLC'nin yok — bu yüzden elle konuyor.
    private var openWatchdog: Task<Void, Never>?

    /// `stop()` biz çağırdık mı?
    ///
    /// ⚠️ VLC durdurulunca `.stopped` yayar ve bu, VOD'da "yayın bitti"
    /// sanılıp `.ended`'e geçilmesine yol açıyordu — oysa kullanıcı sadece
    /// ekranı kapatmıştı.
    private var didStopManually = false
    private var lastReportedSize: CGSize = .zero
    private var videoFit: VideoFit = .fit
    /// Motorun **tek** çizim yüzeyi.
    ///
    /// ⚠️ Güçlü tutuluyor ve her istekte yenisi üretilmiyor — kasıtlı.
    /// VLCKit `drawable`'ı yalnızca video çıkışı kurulurken dikkate alır;
    /// oynatma sürerken yeni bir görünüme atamak **işe yaramaz**, çıkış
    /// eski görünüme bağlı kalır ve yeni yüzey siyah görünür. Gerçek
    /// cihazda mini oynatıcıdan tam ekrana geçince yaşanan tam olarak
    /// buydu (kanal değiştirince düzelmesi de bunu doğruluyordu: yeni
    /// medya yüklenince çıkış baştan kuruluyor).
    ///
    /// Çözüm: aynı görünüm iki ekran arasında **taşınır**. `addSubview`
    /// onu eski üst görünümden zaten çıkarır, çıkış hiç bozulmaz.
    /// Ömrü `teardown()` ile biter; SwiftUI'a bırakılamaz çünkü devir
    /// anında eski taşıyıcı yok edilirken yeni taşıyıcı henüz istemiş
    /// olmayabilir ve zayıf referans o aralıkta ölürdü.
    private var surface: UIView?

    /// Kullanıcının seçtiği hız.
    ///
    /// ⚠️ VLC'de `rate` medya değişince 1.0'a döner; `play()` bunu
    /// yeniden uygular (aynı tuzak `AVPlayerEngine`'de de var).
    private var preferredRate: Float = 1.0

    /// Kaldığı yerden devam saniyesi — medya açılana kadar uygulanamaz.
    ///
    /// ⚠️ VLC'de `time` ataması medya **açılmadan** sessizce yutulur:
    /// `load()` içinde atansaydı film hep baştan başlardı. Bu yüzden
    /// istek saklanır ve ilk oynatılabilir durumda uygulanır.
    private var pendingSeek: TimeInterval?
    private var loadGeneration = 0

    /// - Parameter audioSession: Testlerde sahte oturum verilebilsin diye dışarıdan alınır.
    ///
    /// ⚠️ Varsayılan **gövdede** üretiliyor: `AudioSessionController`
    /// `@MainActor` izole ve varsayılan parametre ifadeleri izolasyonsuz
    /// bağlamda değerlendirilir (bkz. `AVPlayerEngine.init` — aynı tuzak).
    public init(
        identifier: String = "vlc",
        audioSession: AudioSessionController? = nil,
        preferences: PlaybackPreferences? = nil
    ) {
        self.identifier = identifier
        self.audioSession = audioSession ?? AudioSessionController()
        self.preferences = preferences

        // ⚠️ Sessiz kurulum: VLC varsayılan olarak her kareyi konsola
        // loglar ve IPTV akışlarında bu saniyede yüzlerce satır demektir.
        self.player = VLCMediaPlayer(options: ["--quiet", "--no-color"])

        var capturedContinuation: AsyncStream<PlaybackEvent>.Continuation!
        self.events = AsyncStream { capturedContinuation = $0 }
        self.continuation = capturedContinuation

        super.init()

        player.delegate = self
        observeInterruptions()
    }

    // MARK: - Yükleme

    public func load(_ item: PlaybackItem) async {
        loadGeneration &+= 1
        let generation = loadGeneration
        openWatchdog?.cancel()
        didStopManually = false
        isLiveContent = item.isLive
        didPublishTracks = false
        lastReportedSize = .zero
        audioTracks = []
        subtitleTracks = []
        trackIndexes = [:]
        selectedAudioTrack = nil
        selectedSubtitleTrack = nil
        pendingSeek = item.isLive ? nil : item.resumeAt
        transition(to: .loading)

        let media = VLCMedia(url: item.url)
        media.addOptions(Self.mediaOptions(
            for: item,
            liveBuffer: preferences?.liveBuffer ?? .balanced
        ))

        await audioSession.activate()
        guard !Task.isCancelled, loadGeneration == generation, !didStopManually else { return }
        player.media = media
        startOpenWatchdog()

        Log.playback.info("VLC yükledi: \(item.format.rawValue, privacy: .public)")
    }

    /// Belirli bir süre içinde oynatma başlamazsa hatayla biter.
    ///
    /// Süre cömert tutuldu: VLC ağır bir MPEG-TS akışını çözerken
    /// gerçekten yavaş açılabilir. Amaç yavaş yayını kesmek değil,
    /// **ölü yayında sonsuza kadar beklememek**.
    private func startOpenWatchdog() {
        openWatchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            self?.failIfStillOpening()
        }
    }

    private func failIfStillOpening() {
        openWatchdog = nil

        // Bir kare bile geldiyse ya da ses akıyorsa sorun yok.
        guard !player.isPlaying, currentState.showsSpinner else { return }

        Log.playback.notice("VLC açılamadı — zaman aşımı")
        fail(with: .playbackFailed(reason:
            "Yayın açılamadı: sunucu yanıt vermiyor. Kanal kapalı olabilir."
        ))
    }

    /// VLC'ye verilecek medya seçenekleri.
    ///
    /// ⚠️ VLC **rastgele HTTP başlığı kabul etmez**; yalnızca bilinen
    /// birkaç seçeneği vardır. IPTV'de kritik olan ikisi karşılanıyor:
    /// `User-Agent` (panellerin çoğu kontrol eder, beklenmedik değerde 403
    /// döner) ve `Referer`. Diğer başlıklar sessizce düşer — AVPlayer'ın
    /// `AVURLAssetHTTPHeaderFieldsKey`'i kadar geniş değil, sınır burada.
    ///
    /// `network-caching`: doğrudan **kanal geçiş hızıdır** — VLC ilk kareyi
    /// çizmeden önce bu kadar milisaniye tampon doldurur.
    ///
    /// ⚠️ Canlıda 3000 ms denenmişti: akıcıydı ama her zapta 3 saniye
    /// siyah ekran demekti. 1500 ms, IPTV sunucularının düzensiz beslemesini
    /// karşılamaya yetiyor ve gecikmeyi yarıya indiriyor. VOD'da tampon
    /// aramayı (seek) yavaşlattığı için daha da düşük tutuluyor.
    /// Cihaz panelinin gerçek piksel sınırı — çözücüye üst sınır olarak
    /// verilir. Panelden büyük kareyi çözmek görüntüyü iyileştirmez,
    /// yalnızca belleği ve pili yer.
    ///
    /// Alt sınır 1920x1080: küçük ekranlı bir cihazda bile kaliteyi
    /// gereğinden fazla kısmamak için. Üstünde bir sınır konmuyor —
    /// iPad Pro paneli neyi gösterebiliyorsa onu alsın.
    static var displayCap: (width: Int, height: Int) {
        let pixels = UIScreen.main.nativeBounds.size
        let long = Int(max(pixels.width, pixels.height))
        let short = Int(min(pixels.width, pixels.height))
        return (max(long, 1920), max(short, 1080))
    }

    static func mediaOptions(
        for item: PlaybackItem,
        liveBuffer: PlaybackPreferences.LiveBuffer = .balanced
    ) -> [String: Any] {
        // VOD'da tampon aramayı (seek) yavaşlattığı için sabit ve düşük;
        // kullanıcı ayarı yalnızca canlıyı etkiler — orada anlamlı çünkü.
        var options: [String: Any] = [
            "network-caching": item.isLive ? liveBuffer.milliseconds : 1000,

            // ⚠️ BELLEK — asıl kazanç burada.
            //
            // Gerçek cihazda ölçüldü: normal kanallarda VLC 117 MB'da
            // duruyor, UHD kanallarda **400-450 MB**'a çıkıyor. Fark
            // doğrudan kare boyutu: 3840x2160 bir NV12 karesi ~12 MB ve
            // çözücü havuzu bunlardan onlarca tutar.
            //
            // Bu taban **kararlı**: tek 4K kanal 3+ dakika açık tutulduğunda
            // bellek 409 -> 390 MB'a indi, tırmanmadı. Yani birikme/sızıntı
            // yok, sadece 4K çözmenin doğal bedeli. En eski desteklenen
            // cihazın ön plan sınırı bile ~1,3 GB olduğu için risk değil.
            //
            // Telefon paneli o pikselleri zaten gösteremiyor — 4K akışı
            // çözüp ekrana sığdırmak için küçültmek saf israf. Uyarlanır
            // (HLS) akışlarda VLC'ye "panelden büyüğünü seçme" deniyor.
            //
            // ⚠️ ÖLÇÜLDÜ — sınırlı fayda. Yalnızca çok kaliteli
            // (multi-variant) akışlarda işler: seçilecek varyant listesi
            // yoksa VLC'nin elinden bir şey gelmez. Test edilen sağlayıcının
            // 4K kanalları tek kaliteli ham TS olduğu için kare 3840x2160
            // kaldı ve bu ayar hiçbir şey değiştirmedi. Uyarlanır kaynak
            // kullanan panellerde kazanç gerçek, o yüzden duruyor — ama
            // buradan bellek düşüşü beklenmemeli.
            //
            // ⚠️ Ekran yansıtmada (mirroring) sınır yine telefon paneline
            // göre kalır; VLC'de AirPlay zaten yok, kabul edilen bedel.
            "adaptive-maxwidth": displayCap.width,
            "adaptive-maxheight": displayCap.height,

            // Donanım çözmeyi açıkça iste. ⚠️ Ölçüm bunun **tek başına
            // belleği düşürmediğini** gösterdi (444 MB -> 453 MB): iOS'ta
            // VLC HEVC'yi zaten ayrı `videotoolbox` modülüyle donanımda
            // çözüyor ve bu anahtar yalnızca `avcodec` yoluna dokunuyor.
            // Zararsız ve nadir codec'lerde işe yarar diye duruyor, ama
            // bellek beklentisi buna bağlanmamalı.
            "avcodec-hw": "videotoolbox"
        ]

        // Başlık adları büyük/küçük harf duyarsız gelebilir.
        for (name, value) in item.headers {
            switch name.lowercased() {
            case "user-agent":
                options["http-user-agent"] = value
            case "referer", "referrer":
                options["http-referrer"] = value
            default:
                continue
            }
        }

        return options
    }

    // MARK: - Denetimler

    public func play() {
        player.play()
        // ⚠️ `play()` sonrası: VLC hızı medya değişiminde sıfırlar ve
        // atama ancak oynatma başladıktan sonra tutar.
        player.rate = preferredRate
    }

    public func pause() {
        // ⚠️ VLC'de `pause()` duraklamışken çağrılınca oynatmayı yeniden
        // başlatabiliyor. `canPause` hem bunu hem de duraklatılamayan
        // canlı akışları kapsıyor (`isPlaying` tamponlama sırasında
        // `false` döndüğü için tek başına yetmiyordu).
        guard player.canPause else { return }
        player.pause()
    }

    public func stop() {
        didStopManually = true
        openWatchdog?.cancel()
        openWatchdog = nil
        player.stop()
        transition(to: .idle)
    }

    public func seek(to seconds: TimeInterval) async {
        guard !isLiveContent, player.isSeekable else { return }
        player.time = VLCTime(int: Int32(max(0, seconds) * 1000))
        reportTime()
    }

    public func setVolume(_ volume: Float) {
        // VLC ölçeği 0–200; sözleşme 0–1.
        player.audio?.volume = Int32((min(max(volume, 0), 1) * 100).rounded())
    }

    public func setRate(_ rate: Float) {
        preferredRate = max(0.5, min(rate, 2.0))
        player.rate = preferredRate
    }

    // MARK: - Görüntü

    public func makeVideoView() -> UIView {
        // Yüzey zaten varsa **aynısı** döner: çağıran onu kendi taşıyıcısına
        // ekleyince görünüm eski üst görünümden çıkıp yenisine taşınır.
        // Yeni bir görünüm üretmek video çıkışını kopardığı için siyah
        // ekrana yol açıyordu (bkz. `surface` üzerindeki not).
        if let surface { return surface }

        let view = VLCVideoSurfaceView()
        view.backgroundColor = .black
        // Doldurma oranı yalnızca ilk karede değil, cihaz döndüğünde de
        // yeniden hesaplanmalı. Düz `UIView` bu değişimi motora bildirmiyordu.
        view.onLayout = { [weak self] in self?.applyVideoFit() }
        surface = view
        player.drawable = view
        applyVideoFit()
        return view
    }

    public func setVideoFit(_ fit: VideoFit) {
        videoFit = fit
        applyVideoFit()
    }

    /// VLC'de "ekranı doldur" `AVLayerVideoGravity` gibi tek satır değil.
    ///
    /// ⚠️ `scaleFactor = 0` "pencereye sığdır" demektir (sığdırma modu).
    /// Doldurmak için oranı **görünümün** oranına zorlamak gerekir; VLC
    /// o zaman taşan kenarları kırpar. Oran `Int8` işaretçi ister —
    /// C API'sinin doğrudan yansıması.
    private func applyVideoFit() {
        guard let surface else { return }

        switch videoFit {
        case .fit:
            player.videoAspectRatio = nil
            player.scaleFactor = 0
        case .fill:
            let size = surface.bounds.size
            guard size.width > 0, size.height > 0 else { return }
            let ratio = "\(Int(size.width)):\(Int(size.height))"
            ratio.withCString { pointer in
                player.videoAspectRatio = UnsafeMutablePointer(mutating: pointer)
            }
        }
    }

    // MARK: - Yaşam döngüsü

    public func teardown() {
        loadGeneration &+= 1
        openWatchdog?.cancel()
        openWatchdog = nil
        didStopManually = true
        player.delegate = nil
        player.stop()
        player.drawable = nil
        // Yüzey güçlü tutulduğu için burada bırakılmalı, yoksa motor
        // bırakıldıktan sonra da bellekte kalır.
        surface?.removeFromSuperview()
        surface = nil
        audioSession.stopObserving()
        audioSession.deactivate()
        continuation.finish()
        Log.playback.info("VLC bırakıldı")
    }

    private func observeInterruptions() {
        audioSession.observeInterruptions { [weak self] interruption in
            guard let self else { return }
            switch interruption {
            case .began:
                self.pause()
            case .endedShouldResume:
                self.play()
            case .endedShouldStay:
                break
            }
        }
    }

    // MARK: - Durum türetme

    /// Tek doğruluk kaynağı: VLC ne diyorsa o.
    ///
    /// ⚠️ `default` bilinçli: `VLCMediaPlayerState` Objective-C enum'u,
    /// sürümler arası yeni durum ekleyebilir (`esAdded` böyle geldi).
    /// Kapsamlı `switch` yazmak bir sonraki VLCKit yükseltmesinde derlemeyi kırardı.
    func syncState() {
        switch player.state {
        case .opening:
            transition(to: .loading)

        case .buffering:
            // VLC oynarken de "buffering" yayar; gerçekten oynuyorsa
            // spinner göstermek titreme yaratır.
            transition(to: player.isPlaying ? .playing : .buffering)

        case .playing:
            // Açıldı: gözcünün işi bitti.
            openWatchdog?.cancel()
            openWatchdog = nil
            applyPendingSeek()
            transition(to: .playing)

        case .paused:
            transition(to: .paused)

        case .stopped:
            // ⚠️ Durduran biz isek bu bir "son" değil: ekran kapanıyor ya da
            // kanal değişiyor. Ayırt edilmezse VOD'da kullanıcı ekrandan
            // çıkarken oynatıcı "yayın bitti" durumuna geçiyordu.
            guard !didStopManually else { break }
            // Canlıda "durdu" bir kopmadır. Yalnızca `.idle` yayınlamak
            // PlayerController'ın otomatik yeniden bağlanma zincirini hiç
            // tetiklemiyordu; hata olayı da gönderilmelidir.
            if isLiveContent {
                fail(with: .playbackFailed(reason: "Canlı yayın kesildi"))
            } else {
                transition(to: .ended)
            }

        case .error:
            fail(with: .playbackFailed(reason:
                "Yayın açılamadı. Sunucu yanıt vermiyor ya da biçim desteklenmiyor."
            ))

        default:
            break
        }

        refreshTracksIfNeeded()
        reportNaturalSize()
    }

    /// Devam konumu ancak medya açıldıktan sonra uygulanabilir.
    private func applyPendingSeek() {
        guard let target = pendingSeek, target > 0, player.isSeekable else { return }
        pendingSeek = nil
        player.time = VLCTime(int: Int32(target * 1000))
    }

    private func fail(with error: AppError) {
        transition(to: .failed(error))
        continuation.yield(.unrecoverableFailure(error))
    }

    private func transition(to state: PlaybackState) {
        guard state != currentState else { return }
        currentState = state
        continuation.yield(.stateChanged(state))
    }

    // MARK: - Zaman ve boyut

    func reportTime() {
        // İlk `.playing` anında medya henüz seek edilebilir olmayabilir.
        // Bekleyen VOD devam konumunu zaman olaylarında da tekrar dene.
        applyPendingSeek()

        let current = TimeInterval(player.time.intValue) / 1000

        // Canlıda süre yok; VOD'da medya uzunluğu açılınca öğrenilir.
        let rawLength = TimeInterval(player.media?.length.intValue ?? 0) / 1000
        let duration: TimeInterval? = (isLiveContent || rawLength <= 0) ? nil : rawLength

        // ⚠️ VLC tampon seviyesini saniye olarak vermez; `position` yalnızca
        // oynatılan konumdur. Tampon çubuğu için elimizde veri yok —
        // uydurmak yerine oynatılan konum bildiriliyor.
        continuation.yield(.timeChanged(
            PlaybackTime(current: current, duration: duration, bufferedUpTo: current)
        ))
    }

    private func reportNaturalSize() {
        let size = player.videoSize
        guard size.width > 0, size.height > 0, size != lastReportedSize else { return }
        lastReportedSize = size

        // Doldurma modu görünümün oranına bağlı; video oranı öğrenilince
        // yeniden uygulanmalı.
        applyVideoFit()

        continuation.yield(.naturalSizeChanged(
            width: Double(size.width),
            height: Double(size.height)
        ))
    }

    // MARK: - İzler (VLCPlaybackEngine+Tracks.swift)

    func publish(audio: [MediaTrack], subtitle: [MediaTrack]) {
        audioTracks = audio
        subtitleTracks = subtitle
        continuation.yield(.tracksDiscovered(audio: audio, subtitle: subtitle))
    }
}
