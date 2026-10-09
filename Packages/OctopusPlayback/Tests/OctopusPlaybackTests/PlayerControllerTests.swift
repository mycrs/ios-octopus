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

    // MARK: - Oynatma niyeti

    func test_toggleWhileBuffering_pausesActiveRequestAndCanResume() async {
        let native = TestEngine(identifier: "native")
        let controller = makeController(native: native)
        await controller.start(makeItem())
        native.emit(.stateChanged(.playing))
        native.emit(.stateChanged(.buffering))
        let buffering = await waitUntil { controller.state == .buffering }
        XCTAssertTrue(buffering)

        await controller.togglePlayPause()

        XCTAssertEqual(native.pauseCount, 1, "Buffering must not turn a pause request into another play")
        XCTAssertEqual(native.playCount, 1)

        // The engine may still report buffering before its pause event arrives.
        // A second explicit toggle now resumes the cancelled request.
        await controller.togglePlayPause()

        XCTAssertEqual(native.pauseCount, 1)
        XCTAssertEqual(native.playCount, 2)
        await controller.finish()
    }

    func test_toggleWhileLoading_preventsPendingLoadFromStartingPlayback() async {
        let native = TestEngine(identifier: "native")
        let gate = SuspendedLoad()
        defer { gate.release() }
        native.beforeLoad = { await gate.suspend() }
        let controller = makeController(native: native)
        let opening = Task { await controller.start(makeItem()) }
        await fulfillment(of: [gate.entered], timeout: 30)
        XCTAssertEqual(controller.state, .loading)
        XCTAssertEqual(native.loadedItems.count, 1)

        await controller.togglePlayPause()

        XCTAssertEqual(native.pauseCount, 1)
        XCTAssertEqual(native.playCount, 0)
        gate.release()
        await opening.value
        XCTAssertEqual(native.playCount, 0, "A cancelled play request must remain cancelled when load completes")
        await controller.finish()
    }

    func test_toggleWhilePaused_resumesWithoutReloading() async {
        let native = TestEngine(identifier: "native")
        let controller = makeController(native: native)
        await controller.start(makeItem())
        controller.pause()
        native.emit(.stateChanged(.paused))
        let paused = await waitUntil { controller.state == .paused }
        XCTAssertTrue(paused)

        await controller.togglePlayPause()

        XCTAssertEqual(native.pauseCount, 1)
        XCTAssertEqual(native.playCount, 2)
        XCTAssertEqual(native.loadedItems.count, 1)
        await controller.finish()
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

    func test_rememberedFallback_opensHLSDirectlyOnFallback() async {
        let native = TestEngine(identifier: "native")
        let fallback = TestEngine(identifier: "fallback")
        let preferences = makePreferences()
        let item = makeItem(url: URL(string: "http://x/live.m3u8"))
        preferences.rememberFallbackEngine(for: item.source.storageKey)
        let controller = makeController(
            native: native, fallback: fallback, preferences: preferences
        )

        await controller.start(item)

        XCTAssertEqual(controller.engineIdentifier, "fallback")
        XCTAssertTrue(native.loadedItems.isEmpty)
        XCTAssertEqual(fallback.loadedItems.count, 1)
        await controller.finish()
    }

    func test_UHDHint_opensHLSDirectlyOnFallback() async {
        let native = TestEngine(identifier: "native")
        let fallback = TestEngine(identifier: "fallback")
        let controller = makeController(native: native, fallback: fallback)
        let item = PlaybackItem(
            source: .liveChannel("uhd"),
            url: URL(string: "http://x/live.m3u8")!,
            title: "Sport UHD",
            isLive: true
        )

        await controller.start(item)

        XCTAssertEqual(controller.engineIdentifier, "fallback")
        XCTAssertTrue(native.loadedItems.isEmpty)
        XCTAssertEqual(fallback.loadedItems.count, 1)
        await controller.finish()
    }

    func test_disabledFallback_ignoresRememberedSourceAndUHDHint() async {
        let native = TestEngine(identifier: "native")
        let fallback = TestEngine(identifier: "fallback")
        let preferences = makePreferences()
        preferences.useFallbackEngine = false
        let item = PlaybackItem(
            source: .liveChannel("uhd"),
            url: URL(string: "http://x/live.m3u8")!,
            title: "Sport UHD",
            isLive: true
        )
        preferences.rememberFallbackEngine(for: item.source.storageKey)
        let controller = makeController(
            native: native, fallback: fallback, preferences: preferences
        )

        await controller.start(item)

        XCTAssertEqual(controller.engineIdentifier, "native")
        XCTAssertTrue(fallback.loadedItems.isEmpty)
        await controller.finish()
    }

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

    func test_resumeWhileBuffering_recoversWithoutAnotherEngineStateEvent() async {
        let native = TestEngine(identifier: "native")
        let fallback = TestEngine(identifier: "fallback")
        let controller = makeController(
            native: native,
            fallback: fallback,
            vodStallTimeout: .milliseconds(25)
        )
        await controller.start(makeItem())
        controller.pause()

        // A delayed engine callback can still report buffering after pause.
        // No watchdog is armed while the user's play request is cancelled.
        native.emit(.stateChanged(.buffering))
        let buffering = await waitUntil { controller.state == .buffering }
        XCTAssertTrue(buffering)
        guard buffering else {
            await controller.finish()
            return
        }

        controller.play()
        // Neither TestEngine.play() nor this test publishes a new state.
        let recovered = await waitUntil {
            controller.engineIdentifier == "fallback" && fallback.playCount == 1
        }

        XCTAssertTrue(recovered, "Resume must restore bounded recovery even if the engine deduplicates buffering")
        XCTAssertEqual(native.pauseCount, 1)
        XCTAssertEqual(native.playCount, 2)
        XCTAssertEqual(native.loadedItems.count, 1)
        XCTAssertTrue(native.didTeardown)
        XCTAssertEqual(fallback.loadedItems.count, 1)
        XCTAssertEqual(fallback.playCount, 1)
        await controller.finish()
    }

    // MARK: - İzleme geçmişi

    func test_authorizationFailureDoesNotSwapOrReconnectLiveEngine() async {
        let native = TestEngine(identifier: "native")
        let fallback = TestEngine(identifier: "fallback")
        let preferences = makePreferences()
        let controller = makeController(native: native, fallback: fallback, preferences: preferences)
        let item = makeItem(isLive: true)
        await controller.start(item)

        native.emit(.unrecoverableFailure(.unauthorized, kind: .authorization))
        _ = await waitUntil { controller.state == .failed(.unauthorized) }

        XCTAssertTrue(fallback.loadedItems.isEmpty)
        XCTAssertEqual(native.loadedItems.count, 1)
        XCTAssertFalse(preferences.requiresFallbackEngine(for: item.source.storageKey))
        await controller.finish()
    }

    func test_networkFailureRetriesSameLiveEngineWithoutRememberingFallback() async {
        let native = TestEngine(identifier: "native")
        let fallback = TestEngine(identifier: "fallback")
        let preferences = makePreferences()
        let controller = makeController(native: native, fallback: fallback, preferences: preferences)
        let item = makeItem(isLive: true)
        await controller.start(item)

        native.emit(.unrecoverableFailure(.network(reason: "fixture"), kind: .network))
        let retried = await waitUntil { native.loadedItems.count == 2 }

        XCTAssertTrue(retried)
        XCTAssertTrue(fallback.loadedItems.isEmpty)
        XCTAssertFalse(preferences.requiresFallbackEngine(for: item.source.storageKey))
        await controller.finish()
    }

    func test_explicitPauseCancelsPendingReconnect() async {
        let native = TestEngine(identifier: "native")
        let controller = makeController(native: native)
        await controller.start(makeItem(isLive: true))
        native.emit(.unrecoverableFailure(.network(reason: "fixture"), kind: .network))
        _ = await waitUntil { controller.state == .buffering }

        controller.pause()
        let restarted = await waitUntil(timeout: 2.2) { native.loadedItems.count > 1 }

        XCTAssertFalse(restarted, "A pending recovery must not undo an explicit pause/background pause")
        await controller.finish()
    }

    func test_decoderFailureSwitchesOnceAndRemembersEngine() async {
        let native = TestEngine(identifier: "native")
        let fallback = TestEngine(identifier: "fallback")
        let preferences = makePreferences()
        let controller = makeController(native: native, fallback: fallback, preferences: preferences)
        let item = makeItem()
        await controller.start(item)

        native.emit(.unrecoverableFailure(.playbackFailed(reason: "fixture"), kind: .decoder))
        let switched = await waitUntil { controller.engineIdentifier == "fallback" }

        XCTAssertTrue(switched)
        XCTAssertTrue(preferences.requiresFallbackEngine(for: item.source.storageKey))
        await controller.finish()
    }

    func test_unknownFailureCompatibilityFallbackIsNotRemembered() async {
        let native = TestEngine(identifier: "native")
        let fallback = TestEngine(identifier: "fallback")
        let preferences = makePreferences()
        let controller = makeController(native: native, fallback: fallback, preferences: preferences)
        let item = makeItem()
        await controller.start(item)

        native.emit(.unrecoverableFailure(.playbackFailed(reason: "fixture")))
        _ = await waitUntil { controller.engineIdentifier == "fallback" }

        XCTAssertFalse(preferences.requiresFallbackEngine(for: item.source.storageKey))
        await controller.finish()
    }

    func test_refererRequiredSourceSelectsFallbackBeforeMakingNativeRequest() async {
        let native = TestEngine(identifier: "native")
        let fallback = TestEngine(identifier: "fallback")
        let controller = makeController(native: native, fallback: fallback)
        let item = PlaybackItem(
            source: .movie(Movie.ID("headers")), url: URL(fileURLWithPath: "/fixture"),
            title: "Fixture", isLive: false, headers: ["Referer": "https://example.invalid"]
        )
        await controller.start(item)

        XCTAssertTrue(native.loadedItems.isEmpty)
        XCTAssertEqual(fallback.loadedItems.count, 1)
        await controller.finish()
    }

    func test_unsupportedAuthorizationHeadersDoNotOpenEitherEngine() async {
        let native = TestEngine(identifier: "native")
        let fallback = TestEngine(identifier: "fallback")
        let controller = makeController(native: native, fallback: fallback)
        let item = PlaybackItem(
            source: .movie(Movie.ID("headers")), url: URL(fileURLWithPath: "/fixture"),
            title: "Fixture", isLive: false, headers: ["Authorization": "fixture"]
        )
        await controller.start(item)

        XCTAssertTrue(native.loadedItems.isEmpty)
        XCTAssertTrue(fallback.loadedItems.isEmpty)
        XCTAssertEqual(controller.failureKind, .unsupportedHeaders)
        if case .failed = controller.state {} else { XCTFail("Header incompatibility must be explicit") }
        await controller.finish()
    }

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
        let native = TestEngine(identifier: "native")
        let gate = SuspendedLoad()
        native.beforeLoad = { await gate.suspend() }
        let controller = makeController(native: native)

        let opening = Task { await controller.start(makeItem()) }
        await fulfillment(of: [gate.entered], timeout: 30)
        XCTAssertEqual(native.loadedItems.count, 1)
        XCTAssertEqual(native.playCount, 0, "Load must remain pending until explicitly released")

        await controller.finish()
        gate.release()
        await opening.value

        XCTAssertTrue(native.didTeardown)
        XCTAssertEqual(native.playCount, 0, "Kapanan ekranın yüklemesi motoru yeniden oynatmamalı")
        XCTAssertEqual(controller.state, .idle)
        XCTAssertNil(controller.session)
    }

    func test_finish_duringReload_doesNotRestartReleasedEngine() async {
        let native = TestEngine(identifier: "native")
        let controller = makeController(native: native)
        await controller.start(channelItem("a"))
        let gate = SuspendedLoad()
        native.beforeLoad = { await gate.suspend() }

        let opening = Task { await controller.start(channelItem("b")) }
        await fulfillment(of: [gate.entered], timeout: 30)
        XCTAssertEqual(native.loadedItems.count, 2)
        XCTAssertEqual(native.playCount, 1)

        await controller.finish()
        gate.release()
        await opening.value

        XCTAssertTrue(native.didTeardown)
        XCTAssertEqual(native.playCount, 1, "A released engine must not play after its pending reload")
        XCTAssertEqual(controller.state, .idle)
        XCTAssertNil(controller.session)
    }

    func test_finish_duringProgressSave_doesNotReleaseNewSession() async {
        let oldEngine = TestEngine(identifier: "old")
        let newEngine = TestEngine(identifier: "new")
        let progress = TestProgressRepository()
        var creates = 0
        let controller = PlayerController(
            resolver: PlaybackEngineResolver(native: {
                creates += 1
                return creates == 1 ? oldEngine : newEngine
            }),
            progress: progress,
            history: TestHistoryRepository(),
            setScreenAwake: { _ in }
        )
        await controller.start(makeItem())
        oldEngine.emit(.timeChanged(PlaybackTime(current: 55, duration: 100, bufferedUpTo: 60)))
        _ = await waitUntil { progress.saveCount == 1 }

        let gate = ProgressSaveGate()
        progress.beforeSave = { await gate.wait() }
        let finishing = Task { await controller.finish() }
        _ = await waitUntil { progress.saveCount == 2 }

        await controller.start(makeItem(url: URL(string: "http://x/new.m3u8"), isLive: true))
        newEngine.emit(.stateChanged(.playing))
        _ = await waitUntil { controller.state == .playing }
        await gate.open()
        await finishing.value

        XCTAssertTrue(oldEngine.didTeardown)
        XCTAssertFalse(newEngine.didTeardown, "Eski kapanış yeni motoru bırakamaz")
        XCTAssertEqual(controller.engineIdentifier, "new")
        XCTAssertEqual(controller.state, .playing)
        XCTAssertEqual(progress.stored[makeItem().source.storageKey]?.positionSeconds, 55)
        progress.beforeSave = nil
        await controller.finish()
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

    func test_recordedChannelFullscreenHandoff_keepsOneLoadAndSession() async throws {
        let native = TestEngine(identifier: "native")
        let controller = makeController(native: native)
        let item = channelItem("sample", isLive: false)
        await controller.start(item)
        native.emit(.stateChanged(.playing))
        _ = await waitUntil { controller.state == .playing }
        let session = try XCTUnwrap(controller.session)

        await controller.start(item)
        await controller.start(item)

        XCTAssertEqual(controller.session, session)
        XCTAssertEqual(native.loadedItems.count, 1)
        XCTAssertEqual(native.playCount, 1)
        XCTAssertFalse(native.didTeardown)
        XCTAssertEqual(controller.currentItem?.isLive, false)
        await controller.finish()
    }

    func test_staleScreenCleanup_doesNotStopNewChannelEvenWithSameURL() async throws {
        let native = TestEngine(identifier: "native")
        let controller = makeController(native: native)
        await controller.start(channelItem("a"))
        native.emit(.stateChanged(.playing))
        _ = await waitUntil { controller.state == .playing }
        let oldSession = try XCTUnwrap(controller.session)

        await controller.start(channelItem("b"))
        let newSession = try XCTUnwrap(controller.session)
        controller.stop(ifCurrent: oldSession)
        await controller.finish(ifCurrent: oldSession)

        XCTAssertEqual(native.loadedItems.count, 2, "Different channel IDs must not share the same-URL shortcut")
        XCTAssertEqual(controller.session, newSession)
        XCTAssertEqual(controller.currentItem?.source, .liveChannel("b"))
        XCTAssertFalse(native.didTeardown)
        await controller.finish()
    }

    func test_surfaceClose_stopsAudioBeforeProgressSaveCompletes() async throws {
        let native = TestEngine(identifier: "native")
        let progress = TestProgressRepository()
        let gate = ProgressSaveGate()
        let controller = makeController(native: native, progress: progress)
        let item = makeItem()
        let itemKey = item.source.storageKey
        await controller.start(item)
        native.emit(.timeChanged(PlaybackTime(current: 42, duration: 120, bufferedUpTo: 60)))
        _ = await waitUntil { progress.stored[itemKey] != nil }
        progress.stored = [:]
        progress.beforeSave = { await gate.wait() }
        let session = try XCTUnwrap(controller.session)

        controller.stop(ifCurrent: session)

        XCTAssertTrue(native.didTeardown)
        XCTAssertEqual(controller.state, .idle)
        XCTAssertNil(controller.session)
        XCTAssertNil(controller.currentItem)
        await gate.open()
        _ = await waitUntil { progress.stored[itemKey] != nil }
        XCTAssertEqual(progress.stored[itemKey]?.positionSeconds, 42)
    }

    func test_sameChannelNewOpening_isProtectedFromPreviousOpeningCleanup() async throws {
        let native = TestEngine(identifier: "native")
        let controller = makeController(native: native)
        await controller.start(channelItem("a"))
        let oldSession = try XCTUnwrap(controller.session)
        // Failed/opening retry is a new session even for the same source.
        native.emit(.stateChanged(.ended))
        _ = await waitUntil { controller.state == .ended }
        await controller.start(channelItem("a"))
        let currentSession = try XCTUnwrap(controller.session)

        controller.stop(ifCurrent: oldSession)

        XCTAssertNotEqual(oldSession, currentSession)
        XCTAssertEqual(controller.session, currentSession)
        XCTAssertFalse(native.didTeardown)
        await controller.finish()
    }

    private func channelItem(_ id: String, isLive: Bool = true) -> PlaybackItem {
        PlaybackItem(
            source: .liveChannel(Channel.ID(id)), url: URL(fileURLWithPath: "/sample.mp4"),
            title: "Sample", isLive: isLive
        )
    }

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

private actor ProgressSaveGate {
    private var isOpen = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}
