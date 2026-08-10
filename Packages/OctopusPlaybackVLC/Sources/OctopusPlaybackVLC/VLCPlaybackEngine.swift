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
    private weak var surface: UIView?

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

        audioSession.activate()
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
    static func mediaOptions(
        for item: PlaybackItem,
        liveBuffer: PlaybackPreferences.LiveBuffer = .balanced
    ) -> [String: Any] {
        // VOD'da tampon aramayı (seek) yavaşlattığı için sabit ve düşük;
        // kullanıcı ayarı yalnızca canlıyı etkiler — orada anlamlı çünkü.
        var options: [String: Any] = [
            "network-caching": item.isLive ? liveBuffer.milliseconds : 1000
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
        let view = VLCVideoSurfaceView()
        view.backgroundColor = .black
        // Doldurma oranı yalnızca ilk karede değil, cihaz döndüğünde de
        // yeniden hesaplanmalı. Düz `UIView` bu değişimi motora bildirmiyordu.
        view.onLayout = { [weak self] in self?.applyVideoFit() }
        // ⚠️ Zayıf tutulur: yüzeyin ömrü SwiftUI'ın elinde. Motor onu
        // hayatta tutarsa ekran kapandıktan sonra da bellekte kalır.
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
        openWatchdog?.cancel()
        openWatchdog = nil
        didStopManually = true
        player.delegate = nil
        player.stop()
        player.drawable = nil
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
