#if DEBUG
import Foundation

enum OnboardingDebugLaunch {
    private static let arguments = ProcessInfo.processInfo.arguments

    static var opensForm: Bool {
        arguments.contains("-startupOnboardingActivation")
            || arguments.contains("-startupOnboardingLoading")
    }

    static var forcedStep: AddPlaylistViewModel.Step? {
        guard arguments.contains("-startupOnboardingLoading") else { return nil }
        return .syncing(.fetchingChannels(done: 642, total: 1_000))
    }
}
#endif
