import UIKit
import OctopusDesignSystem

/// SwiftUI'ın erişemediği UIKit görünüm ayarları.
/// Yalnızca açılışta bir kez çalışır.
enum Appearance {

    static func apply() {
        let background = UIColor(Theme.Palette.background)

        let tabBar = UITabBarAppearance()
        tabBar.configureWithOpaqueBackground()
        tabBar.backgroundColor = background
        UITabBar.appearance().standardAppearance = tabBar
        UITabBar.appearance().scrollEdgeAppearance = tabBar

        let navigationBar = UINavigationBarAppearance()
        navigationBar.configureWithOpaqueBackground()
        navigationBar.backgroundColor = background
        navigationBar.titleTextAttributes = [
            .foregroundColor: UIColor(Theme.Palette.textPrimary)
        ]
        navigationBar.largeTitleTextAttributes = [
            .foregroundColor: UIColor(Theme.Palette.textPrimary)
        ]
        UINavigationBar.appearance().standardAppearance = navigationBar
        UINavigationBar.appearance().scrollEdgeAppearance = navigationBar
        UINavigationBar.appearance().compactAppearance = navigationBar
    }
}
