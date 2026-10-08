import XCTest
import OctopusDomain
@testable import OctopusPlayback

@MainActor
final class PlaybackDiagnosticSnapshotTests: XCTestCase {
    func test_exportClassifiesFailureWithoutItsSensitiveMessage() throws {
        let snapshot = PlaybackDiagnosticSnapshot(
            capturedAt: Date(timeIntervalSince1970: 0), engine: .native,
            state: .failed(.network(reason: "https://private-host/live/user/secret-password/1.ts")),
            format: .hls, isLive: true, firstVideoFrameReady: false,
            audioTrackCount: 1, subtitleTrackCount: 0, supportsAirPlay: true,
            pictureInPictureAvailable: false, fallbackAttempted: false, reconnectAttempt: 1,
            fallbackAvailable: true
        )
        let encoded = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)

        XCTAssertEqual(snapshot.state, .failed)
        XCTAssertEqual(snapshot.failure, .network)
        let decoded = try JSONDecoder().decode(PlaybackDiagnosticSnapshot.self, from: Data(encoded.utf8))
        XCTAssertTrue(decoded.fallbackAvailable)
        XCTAssertFalse(encoded.contains("private-host"))
        XCTAssertFalse(encoded.contains("secret-password"))
        XCTAssertFalse(encoded.contains("https://"))
    }
}
