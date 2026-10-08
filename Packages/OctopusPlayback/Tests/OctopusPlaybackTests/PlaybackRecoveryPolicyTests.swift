import XCTest
import AVFoundation
import OctopusDomain
@testable import OctopusPlayback

final class PlaybackRecoveryPolicyTests: XCTestCase {
    func test_httpAuthorizationAndMissingResourcesNeverSwitchDecoder() {
        for status in [401, 403, 404, 410] {
            let failure = AVPlayerEngine.classifiedFailure(statusCode: status, error: nil)
            XCTAssertEqual(PlaybackRecoveryPolicy.action(for: failure.error, kind: failure.kind), .stop)
            XCTAssertFalse(failure.kind.remembersFallback)
        }
    }

    func test_temporaryHTTPFailuresRetryCurrentEngine() {
        for status in [429, 500, 502, 503, 504] {
            let failure = AVPlayerEngine.classifiedFailure(statusCode: status, error: nil)
            XCTAssertEqual(PlaybackRecoveryPolicy.action(for: failure.error, kind: failure.kind), .retryCurrent)
            XCTAssertFalse(failure.kind.remembersFallback)
        }
    }

    func test_wrappedNetworkErrorRemainsNetworkError() {
        let transport = NSError(domain: NSURLErrorDomain, code: URLError.timedOut.rawValue)
        let wrapper = NSError(
            domain: AVFoundationErrorDomain, code: -11800,
            userInfo: [NSUnderlyingErrorKey: transport]
        )
        let failure = AVPlayerEngine.classifiedFailure(statusCode: 0, error: wrapper)
        XCTAssertEqual(failure.kind, .network)
        XCTAssertEqual(PlaybackRecoveryPolicy.action(for: failure.error, kind: failure.kind), .retryCurrent)
    }

    func test_decoderAndBlindVideoFailuresCanBeRemembered() {
        let failure = AVPlayerEngine.classifiedFailure(
            statusCode: 0,
            error: NSError(domain: AVFoundationErrorDomain, code: AVError.Code.decodeFailed.rawValue)
        )
        XCTAssertEqual(failure.kind, .decoder)
        XCTAssertTrue(failure.kind.remembersFallback)
        XCTAssertTrue(PlaybackFailureKind.videoNotRendered.remembersFallback)
        XCTAssertEqual(PlaybackRecoveryPolicy.action(for: failure.error, kind: failure.kind), .tryFallback)
    }

    func test_containerOrUnknownFailuresDoNotCreatePermanentDecoderPreference() {
        let failure = AVPlayerEngine.classifiedFailure(
            statusCode: 0,
            error: NSError(domain: AVFoundationErrorDomain, code: AVError.Code.failedToParse.rawValue)
        )
        XCTAssertEqual(failure.kind, .unsupportedFormat)
        XCTAssertFalse(failure.kind.remembersFallback)
        XCTAssertFalse(PlaybackFailureKind.unknown.remembersFallback)
    }

    func test_legacyEngineAuthorizationStillStopsWithoutStructuredKind() {
        XCTAssertEqual(PlaybackRecoveryPolicy.action(for: .unauthorized, kind: .unknown), .stop)
        XCTAssertEqual(PlaybackRecoveryPolicy.action(for: .notFound, kind: .unknown), .stop)
        XCTAssertEqual(PlaybackRecoveryPolicy.action(for: .connectionLimitReached, kind: .unknown), .stop)
    }

    func test_publicUserAgentHeaderAndExplicitFallbackHeaderRouting() {
        XCTAssertNil(AVPlayerEngine.headerFailure(for: ["user-agent": "Octopus/1.0"]))
        XCTAssertEqual(
            AVPlayerEngine.headerFailure(for: ["User-Agent": "Octopus/1.0", "Referer": "https://example.invalid"])?.kind,
            .requiresFallbackHeaders
        )
        XCTAssertEqual(
            AVPlayerEngine.headerFailure(for: ["Authorization": "test fixture"])?.kind,
            .unsupportedHeaders
        )
    }
}
