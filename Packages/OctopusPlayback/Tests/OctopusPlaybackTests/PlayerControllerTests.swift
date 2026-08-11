import XCTest
import OctopusDomain
@testable import OctopusPlayback

/// Koordinatörün üç sözü burada kanıtlanır:
/// yedeğe düşme, kaldığı yerden devam, ilerleme kaydı.
/// Üçü de motordan bağımsızdır — bu yüzden sahte motorla test edilir.
@MainActor
final class PlayerControllerTests: XCTestCase {

    // MARK: - Başlatma

    func test_start_loadsAndPlays() async {
        let native = TestEngine(identifier: "native")
        let controller = makeController(native: native)

        await controller.start(makeItem())

        XCTAssertEqual(native.loadedItems.count, 1)
        XCTAssertEqual(native.playCount, 1, "Yükleme tek başına oynatmaz; play çağrılmalı")
        XCTAssertEqual(controller.engineIdentifier, "native")
    }

    // MARK: - Kaldığı yerden devam

    func test_start_appliesSavedPosition() async {
        let native = TestEngine(identifier: "native")
        let progress = TestProgressRepository()
        let item = makeItem()

        progress.stored[item.source.storageKey] = PlaybackProgress(
            itemKey: item.source.storageKey,
            positionSeconds: 420,
            durationSeconds: 3600,
            updatedAt: Date()
        )

        let controller = makeController(native: native, progress: progress)
        await controller.start(item)

        XCTAssertEqual(native.loadedItems.first?.resumeAt, 420)
    }

    /// ⚠️ Bitmiş içerik baştan başlamalı: kullanıcı filmi tekrar açtığında
    /// son saniyesine atlamak istemez.
    func test_start_ignoresFinishedProgress() async {
        let native = TestEngine(identifier: "native")
        let progress = TestProgressRepository()
        let item = makeItem()

        progress.stored[item.source.storageKey] = PlaybackProgress(
            itemKey: item.source.storageKey,
            positionSeconds: 3550,      // %98 — bitmiş sayılır
            durationSeconds: 3600,
            updatedAt: Date()
        )

        let controller = makeController(native: native, progress: progress)
        await controller.start(item)

        XCTAssertNil(native.loadedItems.first?.resumeAt)
    }

    // MARK: - Yedek motora düşme

    func test_unrecoverableFailure_switchesToFallback() async {
        let native = TestEngine(identifier: "native")
        let fallback = TestEngine(identifier: "fallback")
        let controller = makeController(native: native, fallback: fallback)

        // `unknown` format: önce AVPlayer denenir, patlarsa VLC'ye düşülür.
        await controller.start(makeItem(url: URL(string: "http://x/y")))
        native.emit(.timeChanged(PlaybackTime(current: 12, duration: 100, bufferedUpTo: 20)))
        native.emit(.unrecoverableFailure(.playbackFailed(reason: "codec")))

        let switched = await waitUntil { controller.engineIdentifier == "fallback" }

        XCTAssertTrue(switched, "Native açamadığında yedek motor devreye girmeliydi")
        XCTAssertTrue(native.didTeardown, "Eski motor bırakılmalı — bağlantı kotası")
        XCTAssertEqual(fallback.playCount, 1)
        // Kullanıcı motor değiştiğini fark etmemeli: kaldığı yerden sürer.
        XCTAssertEqual(fallback.loadedItems.first?.resumeAt, 12)
    }

    func test_unrecoverableFailure_withoutFallback_staysPut() async {
        let native = TestEngine(identifier: "native")
        let controller = makeController(native: native)

        await controller.start(makeItem(url: URL(string: "http://x/y")))
        native.emit(.stateChanged(.failed(.playbackFailed(reason: "codec"))))
        native.emit(.unrecoverableFailure(.playbackFailed(reason: "codec")))

        let reported = await waitUntil {
            if case .failed = controller.state { return true }
            return false
        }

        XCTAssertTrue(reported, "Yedek yokken hata kullanıcıya gösterilmeli")
        XCTAssertEqual(controller.engineIdentifier, "native")
        XCTAssertFalse(native.didTeardown)
    }

    /// Sonsuz döngü koruması: yedek de açamazsa üçüncü bir deneme olmaz.
    func test_fallbackFailure_doesNotLoop() async {
        let native = TestEngine(identifier: "native")
        let fallback = TestEngine(identifier: "fallback")
        let controller = makeController(native: native, fallback: fallback)

        await controller.start(makeItem(url: URL(string: "http://x/y")))
        native.emit(.unrecoverableFailure(.playbackFailed(reason: "codec")))
        _ = await waitUntil { controller.engineIdentifier == "fallback" }

        fallback.emit(.unrecoverableFailure(.playbackFailed(reason: "yine olmadı")))
        // Kısa bir pencere: yanlışlıkla yeniden yükleme yapılırsa yakalanır.
        _ = await waitUntil(timeout: 0.5) { fallback.loadedItems.count > 1 }

        XCTAssertEqual(fallback.loadedItems.count, 1, "İkinci kez yedeğe düşülmemeli")
    }

    func test_disabledFallback_routesUnsupportedFormatToNative() async {
        let native = TestEngine(identifier: "native")
        let fallback = TestEngine(identifier: "fallback")
        let preferences = makePreferences()
        preferences.useFallbackEngine = false
        let controller = makeController(
            native: native,
            fallback: fallback,
            preferences: preferences
        )

        await controller.start(makeItem(url: URL(fileURLWithPath: "/film.mkv")))

        XCTAssertEqual(controller.engineIdentifier, "native")
        XCTAssertEqual(native.loadedItems.count, 1)
        XCTAssertTrue(fallback.loadedItems.isEmpty)
    }

    func test_stalledStream_switchesToFallbackInsteadOfSpinningForever() async {
        let native = TestEngine(identifier: "native")
        let fallback = TestEngine(identifier: "fallback")
        let controller = makeController(
            native: native,
            fallback: fallback,
            liveStallTimeout: .milliseconds(25),
            vodStallTimeout: .milliseconds(25)
        )

        await controller.start(makeItem(url: URL(string: "http://x/y")))
        native.emit(.stateChanged(.buffering))

        let switched = await waitUntil { controller.engineIdentifier == "fallback" }

        XCTAssertTrue(switched, "Yanıt vermeyen motor sonsuza kadar spinner'da kalmamalı")
    }

    // MARK: - İzleme geçmişi

    func test_history_isRecordedOnceWhenPlaybackActuallyStarts() async {
        let native = TestEngine(identifier: "native")
        let history = TestHistoryRepository()
        let controller = makeController(native: native, history: history)

        await controller.start(makeItem())
        XCTAssertTrue(history.recorded.isEmpty, "Yükleme tek başına 'izlendi' değildir")

        native.emit(.stateChanged(.playing))
        _ = await waitUntil { !history.recorded.isEmpty }

        // Duraklat/devam et döngüsü geçmişi çoğaltmamalı.
        native.emit(.stateChanged(.paused))
        native.emit(.stateChanged(.playing))
        _ = await waitUntil(timeout: 0.5) { history.recorded.count > 1 }

        XCTAssertEqual(history.recorded.count, 1)
    }

    // MARK: - İlerleme kaydı

    func test_progress_isThrottled() async {
        let native = TestEngine(identifier: "native")
        let progress = TestProgressRepository()
        var clock = Date(timeIntervalSince1970: 0)

        let controller = makeController(
            native: native,
            progress: progress,
            now: { clock }
        )
        await controller.start(makeItem())

        // İlk olay yazar (kayıt yok), sonraki iki olay aralık dolmadığı için yazmaz.
        native.emit(.timeChanged(PlaybackTime(current: 10, duration: 100, bufferedUpTo: 12)))
        _ = await waitUntil { progress.saveCount == 1 }

        native.emit(.timeChanged(PlaybackTime(current: 11, duration: 100, bufferedUpTo: 13)))
        native.emit(.timeChanged(PlaybackTime(current: 12, duration: 100, bufferedUpTo: 14)))
        _ = await waitUntil(timeout: 0.5) { progress.saveCount > 1 }
        XCTAssertEqual(progress.saveCount, 1, "5 sn dolmadan tekrar yazılmamalı")

        clock = Date(timeIntervalSince1970: 6)
        native.emit(.timeChanged(PlaybackTime(current: 16, duration: 100, bufferedUpTo: 20)))
        let wroteAgain = await waitUntil { progress.saveCount == 2 }

        XCTAssertTrue(wroteAgain, "Aralık dolunca yazmalı")
        XCTAssertEqual(progress.stored[makeItem().source.storageKey]?.positionSeconds, 16)
    }

    /// ⚠️ Canlıda konumun anlamı yok; "devam et" rafına canlı kanal düşerse
    /// kullanıcı saatler önceki bir ana dönmeye çalışırdı.
    func test_progress_isNotSavedForLiveContent() async {
        let native = TestEngine(identifier: "native")
        let progress = TestProgressRepository()
        let controller = makeController(native: native, progress: progress)

        await controller.start(makeItem(isLive: true))
        native.emit(.timeChanged(PlaybackTime(current: 30, duration: nil, bufferedUpTo: 35)))
        _ = await waitUntil(timeout: 0.5) { progress.saveCount > 0 }

        XCTAssertEqual(progress.saveCount, 0)
    }

    // MARK: - Kapanış

    func test_finish_savesAndReleases() async {
        let native = TestEngine(identifier: "native")
        let progress = TestProgressRepository()
        let controller = makeController(native: native, progress: progress)

        await controller.start(makeItem())
        native.emit(.timeChanged(PlaybackTime(current: 55, duration: 100, bufferedUpTo: 60)))
        _ = await waitUntil { controller.time.current == 55 }

        await controller.finish()

        XCTAssertTrue(native.didTeardown, "Motor bırakılmazsa IPTV bağlantı kotası dolar")
        XCTAssertEqual(progress.stored[makeItem().source.storageKey]?.positionSeconds, 55)
        XCTAssertEqual(controller.state, .idle)
    }

    func test_finish_clearsPublishedSessionState() async {
        let native = TestEngine(identifier: "native")
        native.supportsAirPlay = true
        let controller = makeController(native: native)
        let track = MediaTrack(id: "audio.1", kind: .audio, label: "Türkçe")

        await controller.start(makeItem())
        controller.setRate(1.5)
        native.emit(.tracksDiscovered(audio: [track], subtitle: []))
        native.emit(.naturalSizeChanged(width: 1920, height: 1080))
        native.emit(.timeChanged(PlaybackTime(current: 40, duration: 100, bufferedUpTo: 50)))
        _ = await waitUntil { controller.time.current == 40 }

        await controller.finish()

        XCTAssertEqual(controller.time, .zero)
        XCTAssertTrue(controller.audioTracks.isEmpty)
        XCTAssertNil(controller.aspectRatio)
        XCTAssertFalse(controller.supportsAirPlay)
        XCTAssertEqual(controller.engineIdentifier, "")
        XCTAssertEqual(controller.rate, 1.0)
    }

    func test_finish_duringLoad_doesNotRestartReleasedEngine() async {
        let native = TestEngine(identifier: "native", loadDelay: .milliseconds(100))
        let controller = makeController(native: native)

        let opening = Task { await controller.start(makeItem()) }
        _ = await waitUntil { !native.loadedItems.isEmpty }

        await controller.finish()
        await opening.value

        XCTAssertTrue(native.didTeardown)
        XCTAssertEqual(native.playCount, 0, "Kapanan ekranın yüklemesi motoru yeniden oynatmamalı")
        XCTAssertEqual(controller.state, .idle)
    }

    // MARK: - Ekranın kararması

    /// ⚠️ Bayrak süreç genelinde: oynatıcı kapandıktan sonra bırakılmazsa
    /// ekran **uygulama boyunca** hiç kararmaz ve pil erir.
    func test_screenStaysAwakeOnlyWhilePlaying() async {
        let native = TestEngine(identifier: "native")
        var awakeLog: [Bool] = []

        let controller = makeController(native: native, setScreenAwake: { awakeLog.append($0) })
        await controller.start(makeItem())

        native.emit(.stateChanged(.playing))
        _ = await waitUntil { awakeLog.last == true }

        native.emit(.stateChanged(.paused))
        _ = await waitUntil { awakeLog.last == false }

        native.emit(.stateChanged(.playing))
        _ = await waitUntil { awakeLog.last == true }

        await controller.finish()

        XCTAssertEqual(awakeLog.last, false, "Kapanışta bayrak bırakılmalı")
    }

    // MARK: - Görüntü yerleşimi

    /// ⚠️ Yerleşim kullanıcıya ait bir tercih, motora ait değil: 4:3 bir
    /// yayında ekranı doldurmayı seçen kullanıcı, yedeğe düşüldüğünde
    /// tercihini kaybetmemeli.
    func test_videoFit_survivesEngineSwitch() async {
        let native = TestEngine(identifier: "native")
        let fallback = TestEngine(identifier: "fallback")
        let controller = makeController(native: native, fallback: fallback)

        await controller.start(makeItem(url: URL(string: "http://x/y")))
        controller.toggleVideoFit()

        XCTAssertEqual(controller.videoFit, .fill)
        XCTAssertEqual(native.videoFit, .fill)

        native.emit(.unrecoverableFailure(.playbackFailed(reason: "codec")))
        _ = await waitUntil { controller.engineIdentifier == "fallback" }

        XCTAssertEqual(fallback.videoFit, .fill, "Tercih yeni motora taşınmalı")
    }

    func test_rate_isClampedAndSurvivesEngineSwitch() async {
        let native = TestEngine(identifier: "native")
        let fallback = TestEngine(identifier: "fallback")
        let controller = makeController(native: native, fallback: fallback)

        await controller.start(makeItem(url: URL(string: "http://x/y")))
        controller.setRate(5)

        XCTAssertEqual(controller.rate, 2.0)
        XCTAssertEqual(native.requestedRates.last, 2.0)

        controller.setRate(1.5)
        native.emit(.unrecoverableFailure(.playbackFailed(reason: "codec")))
        _ = await waitUntil { controller.engineIdentifier == "fallback" }

        XCTAssertEqual(controller.rate, 1.5)
        XCTAssertEqual(fallback.requestedRates.last, 1.5)
    }

    func test_volumeGestureIsClampedAndSurvivesEngineSwitch() async {
        let native = TestEngine(identifier: "native")
        let fallback = TestEngine(identifier: "fallback")
        let controller = makeController(native: native, fallback: fallback)

        await controller.start(makeItem(url: URL(string: "http://x/y")))
        controller.setVolume(1.5)
        XCTAssertEqual(controller.volume, 1)

        controller.setVolume(0.35)
        native.emit(.unrecoverableFailure(.playbackFailed(reason: "codec")))
        _ = await waitUntil { controller.engineIdentifier == "fallback" }

        XCTAssertEqual(controller.volume, 0.35)
        XCTAssertEqual(fallback.requestedVolumes.last, 0.35)
    }

    func test_endedVOD_restartsFromBeginning() async {
        let native = TestEngine(identifier: "native")
        let controller = makeController(native: native)

        await controller.start(makeItem())
        native.emit(.stateChanged(.ended))
        _ = await waitUntil { controller.state == .ended }

        await controller.togglePlayPause()

        XCTAssertEqual(native.loadedItems.count, 2)
        XCTAssertEqual(native.loadedItems.last?.resumeAt, 0)
        XCTAssertEqual(native.playCount, 2)
    }

    // MARK: - Sarma sınırları

    func test_skip_staysWithinBounds() async {
        let native = TestEngine(identifier: "native")
        let controller = makeController(native: native)

        await controller.start(makeItem())
        native.emit(.timeChanged(PlaybackTime(current: 95, duration: 100, bufferedUpTo: 100)))
        _ = await waitUntil { controller.time.current == 95 }

        await controller.skip(by: 30)
        XCTAssertEqual(native.seekedTo.last, 100, "Süreyi aşmamalı")

        native.emit(.timeChanged(PlaybackTime(current: 3, duration: 100, bufferedUpTo: 100)))
        _ = await waitUntil { controller.time.current == 3 }

        await controller.skip(by: -30)
        XCTAssertEqual(native.seekedTo.last, 0, "Negatife inmemeli")
    }

    // MARK: - Yardımcılar

    private func makeController(
        native: TestEngine,
        fallback: TestEngine? = nil,
        progress: TestProgressRepository = TestProgressRepository(),
        history: TestHistoryRepository = TestHistoryRepository(),
        preferences: PlaybackPreferences? = nil,
        liveStallTimeout: Duration = .seconds(20),
        vodStallTimeout: Duration = .seconds(45),
        now: @escaping () -> Date = Date.init,
        setScreenAwake: @escaping @MainActor (Bool) -> Void = { _ in }
    ) -> PlayerController {
        // Tip açıkça yazılıyor: `() -> TestEngine` kendiliğinden
        // `() -> PlaybackEngine`'e dönüşmez.
        var fallbackFactory: PlaybackEngineResolver.EngineFactory?
        if let fallback {
            fallbackFactory = { fallback }
        }

        let resolver = PlaybackEngineResolver(
            native: { native },
            fallback: fallbackFactory
        )
        return PlayerController(
            resolver: resolver,
            progress: progress,
            history: history,
            preferences: preferences,
            saveInterval: 5,
            liveStallTimeout: liveStallTimeout,
            vodStallTimeout: vodStallTimeout,
            now: now,
            setScreenAwake: setScreenAwake
        )
    }

    private func makePreferences() -> PlaybackPreferences {
        let suite = "PlayerControllerTests.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite) ?? .standard
        store.removePersistentDomain(forName: suite)
        return PlaybackPreferences(store: store)
    }

    private func makeItem(
        url: URL? = nil,
        isLive: Bool = false
    ) -> PlaybackItem {
        PlaybackItem(
            source: .movie(Movie.ID("m-1")),
            url: url ?? URL(fileURLWithPath: "/dev/null"),
            title: "Test filmi",
            isLive: isLive
        )
    }
}
