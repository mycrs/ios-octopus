import XCTest
import AVFoundation
import UIKit
import OctopusDomain
@testable import OctopusPlayback

/// Motorun **sözleşmeye uyduğunu** doğrular: durum makinesi, hata yolu,
/// kaynak bırakma. Gerçek bir yayın oynatmak CI'da ağa bağımlı ve kırılgan
/// olurdu; bunun yerine var olmayan bir yerel dosya kullanılıyor — hata
/// yolu ağ olmadan, deterministik biçimde tetikleniyor.
@MainActor
final class AVPlayerEngineTests: XCTestCase {

    // MARK: - İstek başlıkları

    func test_assetOptions_omitsHeaderKeyWhenThereAreNone() {
        let options = AVPlayerEngine.assetOptions(for: makeItem(headers: [:]))

        XCTAssertTrue(
            options.isEmpty,
            "Başlık yokken belgelenmemiş anahtara hiç dokunulmamalı"
        )
    }

    func test_assetOptions_carriesHeaders() {
        let item = makeItem(headers: ["User-Agent": "Octopus/1.0"])
        let options = AVPlayerEngine.assetOptions(for: item)

        // ⚠️ IPTV'de bu başlık olmadan panellerin çoğu 403 döner.
        let headers = options["AVURLAssetHTTPHeaderFieldsKey"] as? [String: String]
        XCTAssertEqual(headers?["User-Agent"], "Octopus/1.0")
    }

    // MARK: - Durum makinesi

    func test_initialState_isIdle() {
        let engine = AVPlayerEngine()
        defer { engine.teardown() }

        XCTAssertEqual(engine.currentState, .idle)
        XCTAssertTrue(engine.audioTracks.isEmpty)
        XCTAssertNil(engine.selectedAudioTrack)
    }

    func test_loadingMissingFile_reachesFailedState() async throws {
        let engine = AVPlayerEngine()
        defer { engine.teardown() }

        await engine.load(makeItem(url: missingFileURL()))

        // Süre değil **koşul** beklenir: yüklü bir CI koşucusunda sabit
        // bekleme rastgele kırmızıya döner (bkz. BRAIN.md § 11.1).
        let failed = await waitUntil {
            if case .failed = engine.currentState { return true }
            return false
        }

        XCTAssertTrue(failed, "Var olmayan dosya .failed durumuna götürmeliydi")
    }

    /// Yedek motora geçiş bu olaya bağlı — düşerse VLC hiç denenmez.
    func test_loadingMissingFile_emitsUnrecoverableFailureEvent() async throws {
        let engine = AVPlayerEngine()

        let received = Task<Bool, Never> {
            for await event in engine.events {
                if case .unrecoverableFailure = event { return true }
            }
            return false
        }

        await engine.load(makeItem(url: missingFileURL()))

        let didFail = await waitUntil {
            if case .failed = engine.currentState { return true }
            return false
        }
        XCTAssertTrue(didFail)

        // Akışı bitir ki yukarıdaki döngü sonuca ulaşsın.
        engine.teardown()
        let sawEvent = await received.value

        XCTAssertTrue(sawEvent, "unrecoverableFailure yayınlanmadı — fallback zinciri kopar")
    }

    // MARK: - Kaynak bırakma

    /// IPTV bağlantı kotası: bırakılmayan akış kullanıcıyı kilitler.
    func test_teardown_finishesEventStream() async {
        let engine = AVPlayerEngine()

        let drained = Task<Bool, Never> {
            for await _ in engine.events {}
            return true   // döngü ancak akış bitince çıkar
        }

        engine.teardown()

        // ⚠️ Önce `await`, sonra assert: `XCTAssert…` bir autoclosure alır
        // ve autoclosure içinde `await` kullanılamaz
        // ("'async' property access in an autoclosure that does not support
        // concurrency" — aynı tuzak `XCTUnwrap(try await …)` ile de yaşandı).
        let didDrain = await drained.value
        XCTAssertTrue(didDrain, "teardown olay akışını kapatmalı")
    }

    func test_stop_returnsToIdle() async {
        let engine = AVPlayerEngine()
        defer { engine.teardown() }

        await engine.load(makeItem(url: missingFileURL()))
        engine.stop()

        XCTAssertEqual(engine.currentState, .idle)
    }

    func test_queuedEndNotification_doesNotEndReplacementItem() async throws {
        let engine = AVPlayerEngine()
        defer { engine.teardown() }
        let reachedEnd = Task {
            for await event in engine.events {
                if case .stateChanged(.ended) = event { return true }
            }
            return false
        }
        await engine.load(makeItem(url: missingFileURL()))
        let oldItem = try XCTUnwrap(engine.player.currentItem)

        // Bildirim ana aktöre iş kuyruğa koyar; yeni içerik o işten önce yüklenir.
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: oldItem)
        await engine.load(makeItem(url: missingFileURL()))
        _ = await waitUntil(timeout: 0.25) { engine.currentState == .ended }
        XCTAssertFalse(engine.player.currentItem === oldItem)
        engine.teardown()
        let incorrectlyEnded = await reachedEnd.value

        XCTAssertFalse(incorrectlyEnded, "Önceki yayının bitişi yeni yayını bitiremez")
    }

    func test_queuedObservations_afterStop_keepEngineIdle() async {
        let engine = AVPlayerEngine()
        defer { engine.teardown() }
        await engine.load(makeItem(url: missingFileURL()))
        engine.stop()

        let changed = await waitUntil(timeout: 0.25) { engine.currentState != .idle }

        XCTAssertFalse(changed, "Bırakılan içeriğin kuyruktaki olayları motoru diriltemez")
        XCTAssertNil(engine.player.currentItem)
    }

    // MARK: - İlk görüntü karesi

    /// Boyut metadata'sı video yüzeyi olmadan da gelir. Bu, ilk karenin
    /// çizime hazır olduğunu kanıtlamaz; siyah ekran gözcüsü açık kalmalı.
    func test_presentationSize_withoutVideoSurface_doesNotCountAsRenderedFrame() async throws {
        let engine = AVPlayerEngine()
        let sizePublished = expectation(description: "Video boyutu olayı yayınlandı")
        let sizeEvents = Task {
            for await event in engine.events {
                if case .naturalSizeChanged(let width, let height) = event, width > 0, height > 0 {
                    sizePublished.fulfill()
                    return
                }
            }
        }
        defer {
            sizeEvents.cancel()
            engine.teardown()
        }
        await engine.load(makeItem(url: try videoFixtureURL()))
        engine.play()

        await fulfillment(of: [sizePublished], timeout: 5)
        XCTAssertFalse(engine.didRenderVideo, "Boyut bilgisi ilk kare sinyali yerine kullanılamaz")
    }

    func test_firstFrameReadiness_isResetWhenReusingSurfaceForAnotherItem() async throws {
        let engine = AVPlayerEngine()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        let host = UIViewController()
        window.rootViewController = host
        window.isHidden = false
        defer {
            engine.teardown()
            window.isHidden = true
            window.rootViewController = nil
        }
        await engine.load(makeItem(url: try videoFixtureURL()))
        let surface = engine.makeVideoView()
        surface.frame = host.view.bounds
        host.view.addSubview(surface)
        host.view.layoutIfNeeded()
        engine.play()

        let rendered = await waitUntil { engine.didRenderVideo }
        XCTAssertTrue(rendered, "AVPlayerLayer'ın ilk kare sinyali izlenmeli")

        await engine.load(makeItem(url: missingFileURL()))
        let failed = await waitUntil {
            if case .failed = engine.currentState { return true }
            return false
        }

        XCTAssertTrue(failed)
        XCTAssertTrue(engine.makeVideoView() === surface, "Zap sırasında yüzey korunmalı")
        XCTAssertFalse(engine.didRenderVideo, "Eski katmanın kare sinyali yeni yayına taşınamaz")
    }

    // MARK: - Canlı yayın davranışı

    func test_seek_isIgnoredForLiveContent() async {
        let engine = AVPlayerEngine()
        defer { engine.teardown() }

        await engine.load(makeItem(url: missingFileURL(), isLive: true))
        await engine.seek(to: 120)

        // Asıl garanti: canlıda arama çökmez ve sessizce yok sayılır.
        XCTAssertTrue(engine.player.currentTime().seconds.isFinite)
    }

    // MARK: - Altyazı kapatma satırı

    func test_subtitleOffTrack_isSynthetic() {
        let track = AVPlayerEngine.makeSubtitleOffTrack()

        XCTAssertEqual(track.id, AVPlayerEngine.subtitleOffTrackID)
        XCTAssertEqual(track.kind, .subtitle)
        // AVFoundation "altyazı yok"u seçenek olarak sunmaz; bu satır
        // olmadan kullanıcı açtığı altyazıyı kapatamaz.
        XCTAssertNil(track.languageCode)
    }

    // MARK: - Yardımcılar

    private func videoFixtureURL() throws -> URL {
        try XCTUnwrap(Bundle.module.url(
            forResource: "video-sample", withExtension: "mp4", subdirectory: "Fixtures"
        ))
    }

    private func makeItem(
        url: URL = URL(fileURLWithPath: "/dev/null"),
        isLive: Bool = false,
        headers: [String: String] = [:]
    ) -> PlaybackItem {
        PlaybackItem(
            source: .liveChannel(Channel.ID("ch-1")),
            url: url,
            title: "Test",
            isLive: isLive,
            headers: headers
        )
    }

    /// Her testte benzersiz: aynı yol için AVFoundation sonucu
    /// önbelleğe alırsa testler birbirini etkilerdi.
    private func missingFileURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("yok-\(UUID().uuidString).mp4")
    }

}
