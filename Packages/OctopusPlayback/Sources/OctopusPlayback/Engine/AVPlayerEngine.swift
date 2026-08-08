import Foundation
import AVFoundation
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

    /// PiP Faz 9'da bağlanacak; şu an UI'da tetikleyici yok.
    /// AVPlayer teknik olarak destekliyor — `true` yazmak, olmayan bir
    /// düğmeyi vaat etmek olurdu.
    public let supportsPictureInPicture = false

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

    private var observations: [NSKeyValueObservation] = []
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var trackDiscovery: Task<Void, Never>?

    private var isLiveContent = false
    private var didReachEnd = false

    /// Kullanıcının seçtiği oynatma hızı.
    ///
    /// ⚠️ `player.play()` hızı **her zaman 1.0'a döndürür**. 1.5x seçip
    /// duraklatıp devam eden kullanıcı normal hıza düşerdi; bu yüzden
    /// `play()` doğrudan `rate` atar.
    private var preferredRate: Float = 1.0

    public init(
        identifier: String = "avplayer",
        audioSession: AudioSessionController = AudioSessionController()
    ) {
        self.identifier = identifier
        self.audioSession = audioSession
        self.player = AVPlayer()

        var capturedContinuation: AsyncStream<PlaybackEvent>.Continuation!
        self.events = AsyncStream { capturedContinuation = $0 }
        self.continuation = capturedContinuation

        // Kanal değiştirirken sesin bir an patlamasını önler.
        player.automaticallyWaitsToMinimizeStalling = true
        observeInterruptions()
    }

    // MARK: - Yükleme

    public func load(_ item: PlaybackItem) async {
        releaseCurrentItem()

        didReachEnd = false
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
        let view = PlayerLayerView()
        view.player = player
        return view
    }

    public func teardown() {
        trackDiscovery?.cancel()
        trackDiscovery = nil
        releaseCurrentItem()
        player.replaceCurrentItem(with: nil)
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
            let reason = playerItem.error?.localizedDescription
                ?? "Yayın açılamadı (bilinmeyen sebep)"
            fail(with: .playbackFailed(reason: reason))
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
