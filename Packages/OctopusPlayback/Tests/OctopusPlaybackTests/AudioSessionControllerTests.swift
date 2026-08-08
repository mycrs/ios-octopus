import XCTest
import AVFoundation
@testable import OctopusPlayback

/// Kesinti kararı saf bir fonksiyon olarak ayrıldı: telefon gelmesini
/// simüle etmek mümkün değil, ama sistemin gönderdiği sözlüğü doğru
/// yorumladığımız burada tam olarak doğrulanabilir.
final class AudioSessionControllerTests: XCTestCase {

    func test_began_isRecognised() {
        let info: [AnyHashable: Any] = [
            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue
        ]

        XCTAssertEqual(AudioSessionController.interpret(info), .began)
    }

    /// Sistem "devam edebilirsin" derse devam edilir.
    func test_endedWithShouldResume_resumes() {
        let info: [AnyHashable: Any] = [
            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
            AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue
        ]

        XCTAssertEqual(AudioSessionController.interpret(info), .endedShouldResume)
    }

    /// ⚠️ Bayrak yokken devam etmek iki sesin üst üste binmesi demektir:
    /// kullanıcı araya başka bir video açmış olabilir.
    func test_endedWithoutShouldResume_staysPaused() {
        let info: [AnyHashable: Any] = [
            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue
        ]

        XCTAssertEqual(AudioSessionController.interpret(info), .endedShouldStay)
    }

    func test_malformedUserInfo_yieldsNoDecision() {
        XCTAssertNil(AudioSessionController.interpret(nil))
        XCTAssertNil(AudioSessionController.interpret([:]))
        XCTAssertNil(AudioSessionController.interpret(["beklenmeyen": "değer"]))
    }
}
