import XCTest
import UIKit
import OctopusDomain
@testable import OctopusPlayback

/// Motor seçimi IPTV'nin en kritik mantığı: yanlış motor = siyah ekran.
/// Bu yüzden karar fonksiyonu saf tutuldu ve burada tam kapsamlı test edilir.
@MainActor
final class PlaybackEngineResolverTests: XCTestCase {

    // MARK: - Yedek motor VARKEN

    func test_withFallback_routesFormatsToCorrectEngine() {
        let resolver = makeResolver(withFallback: true)

        // AVPlayer'ın açabildikleri → native (PiP/AirPlay kazanılır)
        XCTAssertEqual(resolver.decide(for: .hls), .native)
        XCTAssertEqual(resolver.decide(for: .mp4), .native)

        // AVPlayer'ın açamadıkları → VLC
        XCTAssertEqual(resolver.decide(for: .mpegTS), .fallback)
        XCTAssertEqual(resolver.decide(for: .mkv), .fallback)
        XCTAssertEqual(resolver.decide(for: .avi), .fallback)
        XCTAssertEqual(resolver.decide(for: .rtsp), .fallback)
        XCTAssertEqual(resolver.decide(for: .rtmp), .fallback)

        // Bilinmeyen: önce ucuz/iyi entegre olanı dene
        XCTAssertEqual(resolver.decide(for: .unknown), .native)
    }

    // MARK: - Yedek motor YOKKEN (VLCKit bağlanmamış olsa bile çalışmalı)

    func test_withoutFallback_neverCrashesAndAlwaysReturnsEngine() {
        let resolver = makeResolver(withFallback: false)

        for format in StreamFormat.allCases {
            XCTAssertEqual(
                resolver.decide(for: format), .native,
                "Yedek yokken her format native'e düşmeli: \(format)"
            )
            // Asıl garanti: her koşulda bir motor döner, nil değil.
            _ = resolver.makeEngine(for: format)
        }

        XCTAssertFalse(resolver.hasFallback)
        XCTAssertNil(resolver.makeRuntimeFallbackEngine())
    }

    // MARK: - Çalışma zamanı fallback zinciri

    func test_runtimeRetry_onlyFromNativeAndOnlyWhenFallbackExists() {
        let withFallback = makeResolver(withFallback: true)
        XCTAssertTrue(withFallback.canRetryWithFallback(after: .native))
        XCTAssertFalse(
            withFallback.canRetryWithFallback(after: .fallback),
            "Zaten VLC'deysek sonsuz döngüye girmemeli"
        )

        let withoutFallback = makeResolver(withFallback: false)
        XCTAssertFalse(withoutFallback.canRetryWithFallback(after: .native))
    }

    func test_makeEngine_producesExpectedEngineIdentity() {
        let resolver = makeResolver(withFallback: true)
        XCTAssertEqual(resolver.makeEngine(for: .hls).identifier, "native")
        XCTAssertEqual(resolver.makeEngine(for: .mpegTS).identifier, "fallback")
    }

    func test_disablingFallback_forcesNativeEvenForUnsupportedFormat() {
        let resolver = makeResolver(withFallback: true)

        XCTAssertEqual(
            resolver.decide(for: .mkv, allowingFallback: false),
            .native
        )
        XCTAssertEqual(
            resolver.makeEngine(for: .mpegTS, allowingFallback: false).identifier,
            "native"
        )
    }

    // MARK: - Yardımcılar

    private func makeResolver(withFallback: Bool) -> PlaybackEngineResolver {
        PlaybackEngineResolver(
            native: { StubEngine(identifier: "native") },
            fallback: withFallback ? { StubEngine(identifier: "fallback") } : nil
        )
    }
}

/// Test amaçlı boş motor. Gerçek motorlar Faz 5'te yazılacak;
/// resolver mantığı onlardan bağımsız olarak bugün doğrulanabilir.
@MainActor
private final class StubEngine: PlaybackEngine {

    let identifier: String
    let events: AsyncStream<PlaybackEvent>

    private(set) var currentState: PlaybackState = .idle
    private(set) var audioTracks: [MediaTrack] = []
    private(set) var subtitleTracks: [MediaTrack] = []
    let selectedAudioTrack: MediaTrack? = nil
    let selectedSubtitleTrack: MediaTrack? = nil
    let supportsPictureInPicture = false
    let supportsAirPlay = false
    let isPictureInPicturePossible = false
    func setPictureInPictureActive(_ active: Bool) {}

    init(identifier: String) {
        self.identifier = identifier
        self.events = AsyncStream { $0.finish() }
    }

    func load(_ item: PlaybackItem) async {}
    func play() {}
    func pause() {}
    func stop() {}
    func seek(to seconds: TimeInterval) async {}
    func setVolume(_ volume: Float) {}
    func setRate(_ rate: Float) {}
    func select(track: MediaTrack) {}
    func setVideoFit(_ fit: VideoFit) {}
    func makeVideoView() -> UIView { UIView() }
    func teardown() {}
}
