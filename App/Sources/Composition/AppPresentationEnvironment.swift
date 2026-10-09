import SwiftUI
import OctopusDesignSystem
import OctopusNavigation
import OctopusPlayback

/// Sheets and UIKit-hosted players start separate presentation trees.
/// Supply the same shared objects at each boundary, including busy form states.
struct AppPresentationEnvironment: ViewModifier {
    @ObservedObject var theme: ThemeController
    @ObservedObject var language: LanguageController
    let router: AppRouter
    let playback: PlaybackPreferences

    func body(content: Content) -> some View {
        content
            .environmentObject(router)
            .environmentObject(theme)
            .environmentObject(language)
            .environmentObject(playback)
            .environment(\.brandColor, theme.accent)
            .environment(\.locale, language.locale)
            .tint(theme.accent)
    }
}

extension RootView {
    var presentationEnvironment: AppPresentationEnvironment {
        AppPresentationEnvironment(
            theme: container.themeController, language: language,
            router: router, playback: container.playbackPreferences
        )
    }
}
