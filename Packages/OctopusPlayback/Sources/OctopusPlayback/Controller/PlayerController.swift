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

    /// Hangi motor çalışıyor? Video yüzeyi motor değişince yeniden kurulmalı,
    /// SwiftUI tarafı bunu `.id()` olarak kullanır.
    @Published public private(set) var engineIdentifier: String = ""

    /// Kullanıcının seçtiği oynatma hızı (canlıda kullanılmaz).
    @Published public private(set) var rate: Float = 1.0

    // MARK: - Bağımlılıklar

    private let resolver: PlaybackEngineResolver
    private let progress: PlaybackProgressRepository
    private let history: WatchHistoryRepository
    private let nowPlaying: NowPlayingCenter
    private let saveInterval: TimeInterval
    private let now: () -> Date

    // MARK: - İç durum

    private var engine: PlaybackEngine?
    private var eventTask: Task<Void, Never>?
    private var item: PlaybackItem?
    private var decision: PlaybackEngineResolver.Decision = .native

    /// Yedek motora **yalnızca bir kez** düşülür; iki motor da açamıyorsa
    /// hata kullanıcıya gösterilir. Aksi hâlde sonsuz döngü riski var.
    private var didAttemptFallback = false

    private var lastSavedAt: Date?
    private var didRecordHistory = false

    /// ⚠️ `nowPlaying` varsayılanı **gövdede** üretiliyor: `@MainActor`
    /// izole bir tipin örneği varsayılan parametre ifadesi olamaz
    /// (bkz. `AVPlayerEngine.init`, aynı tuzak CI'da yakalandı).
    public init(
        resolver: PlaybackEngineResolver,
        progress: PlaybackProgressRepository,
        history: WatchHistoryRepository,
        nowPlaying: NowPlayingCenter? = nil,
        saveInterval: TimeInterval = 5,
        now: @escaping () -> Date = Date.init
    ) {
        self.resolver = resolver
        self.progress = progress
        self.history = history
        self.nowPlaying = nowPlaying ?? NowPlayingCenter()
        self.saveInterval = saveInterval
        self.now = now
    }

    // MARK: - Yaşam döngüsü

    /// İçeriği açar. Devam konumu burada eklenir.
    public func start(_ requested: PlaybackItem) async {
        didAttemptFallback = false
        didRecordHistory = false
        lastSavedAt = nil

        let prepared = await withResumePosition(requested)
        item = prepared
        decision = resolver.decide(for: prepared.format)

        attachRemoteCommands(isLive: prepared.isLive)
        await attach(resolver.makeEngine(for: prepared.format), loading: prepared)
    }

    /// Kilit ekranı düğmelerini bu oturuma bağlar.
    private func attachRemoteCommands(isLive: Bool) {
        nowPlaying.attach(
            handlers: NowPlayingCenter.Handlers(
                play: { [weak self] in self?.play() },
                pause: { [weak self] in self?.pause() },
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

    private func attach(_ newEngine: PlaybackEngine, loading target: PlaybackItem) async {
        eventTask?.cancel()
        engine?.teardown()

        engine = newEngine
        engineIdentifier = newEngine.identifier
        rate = 1.0

        // ⚠️ Abonelik yüklemeden **önce** kurulur. Ters sırada, yükleme
        // sırasında düşen olaylar (ör. anında gelen hata) kaybolurdu:
        // `AsyncStream` dinleyicisi yokken yayınlanan değer yok olur
        // (bkz. BRAIN.md § 11.1 — aynı tuzak testlerde yaşandı).
        eventTask = Task { [weak self] in
            for await event in newEngine.events {
                self?.handle(event)
            }
        }

        await newEngine.load(target)
        newEngine.play()
    }

    /// Ekran kapanırken çağrılır. **Atlanamaz.**
    public func finish() async {
        await saveProgress(force: true)

        eventTask?.cancel()
        eventTask = nil
        engine?.teardown()
        engine = nil
        // Atlanırsa kilit ekranında çalmayan bir içerik asılı kalır.
        nowPlaying.clear()
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

    public func togglePlayPause() {
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
        engine?.setRate(newRate)
        rate = newRate
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
            if newState == .playing { recordHistoryOnce() }
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
            Task { await handleFailure(error) }
        }
    }

    /// Native motor açamadı — yedeği dene.
    private func handleFailure(_ error: AppError) async {
        guard
            !didAttemptFallback,
            resolver.canRetryWithFallback(after: decision),
            let fallback = resolver.makeRuntimeFallbackEngine(),
            let target = item
        else {
            // Yedek yok ya da o da başarısız: hata zaten `state`'te.
            Log.playback.error("Oynatma başarısız, yedek denenemedi")
            return
        }

        didAttemptFallback = true
        decision = .fallback
        Log.playback.notice("Native motor açamadı, yedeğe geçiliyor: \(String(describing: error))")

        // Kaldığı yer korunur: kullanıcı motor değiştiğini fark etmemeli.
        let resumed = target.resuming(at: time.current > 1 ? time.current : target.resumeAt)
        await attach(fallback, loading: resumed)
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
