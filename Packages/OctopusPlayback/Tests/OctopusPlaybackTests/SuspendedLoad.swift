import XCTest

/// The test bounds entry using XCTest, then explicitly releases completion.
/// Main-actor isolation prevents release from racing continuation registration.
@MainActor
final class SuspendedLoad {
    let entered = XCTestExpectation(description: "Engine load entered")
    private var hasEntered = false
    private var isReleased = false
    private var completion: CheckedContinuation<Void, Never>?

    func suspend() async {
        if !hasEntered {
            hasEntered = true
            entered.fulfill()
        }
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            completion = continuation
        }
    }

    func release() {
        isReleased = true
        let pending = completion
        completion = nil
        pending?.resume()
    }
}
