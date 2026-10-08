import XCTest
import Foundation
@testable import OctopusPlayback

@MainActor
final class AudioSessionWorkerTests: XCTestCase {
    func test_activationRunsOutsideMainThreadAndIsAwaited() async {
        let activated = expectation(description: "Background activation completed")
        let worker = AudioSessionWorker(activate: {
            XCTAssertFalse(Thread.isMainThread)
            activated.fulfill()
        }, deactivate: {})

        await worker.activate()
        await fulfillment(of: [activated], timeout: 1)
    }

    func test_handoffDeactivationCompletesBeforeNextActivation() async {
        let calls = AudioCallRecorder()
        let worker = AudioSessionWorker(activate: {
            calls.append("activate")
        }, deactivate: {
            XCTAssertFalse(Thread.isMainThread)
            calls.append("deactivate")
        })
        worker.deactivate()
        await worker.activate()

        XCTAssertEqual(calls.values, ["deactivate", "activate"])
    }

    func test_cancelledLoadDoesNotActivateAudioSession() async {
        let calls = AudioCallRecorder()
        let worker = AudioSessionWorker(activate: {
            calls.append("activate")
        }, deactivate: {})
        let pending = Task { await worker.activate() }
        pending.cancel()
        await pending.value

        XCTAssertTrue(calls.values.isEmpty)
    }
}

private final class AudioCallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    func append(_ value: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(value)
    }
    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
