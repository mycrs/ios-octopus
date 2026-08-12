#if DEBUG
import Foundation
import OctopusDomain

enum OnboardingDebugLaunch {
    private static let arguments = ProcessInfo.processInfo.arguments

    static var opensForm: Bool {
        arguments.contains("-startupOnboardingActivation")
            || arguments.contains("-startupOnboardingLoading")
            || arguments.contains("-startupOnboardingResellerQuick")
    }

    static var showsResellerQuickLogin: Bool {
        arguments.contains("-startupOnboardingResellerQuick")
    }

    static var forcedStep: AddPlaylistViewModel.Step? {
        guard arguments.contains("-startupOnboardingLoading") else { return nil }
        return .syncing(.finished(at: Date(), counts: forcedCounts ?? .empty))
    }

    static var forcedCounts: SyncContentCounts? {
        guard arguments.contains("-startupOnboardingLoading") else { return nil }
        return SyncContentCounts(channels: 1_284, movies: 3_642, series: 418)
    }
}
#endif
