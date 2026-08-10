#if DEBUG
import Foundation
import OctopusDomain

/// GitHub simülatör karelerinde hesap kartlarının da doğrulanmasını sağlar.
/// Üretim derlemesine girmez ve kalıcı veriyi değiştirmez.
enum HomeDebugPresentation {
    static func account(fallback: HomeAccount?) -> HomeAccount? {
        guard ProcessInfo.processInfo.arguments.contains("-seedDemoData"),
              let host = URL(string: "https://demo.example.com")
        else { return fallback }

        let expiry = Calendar.current.date(byAdding: .day, value: 45, to: Date())
        let playlist = Playlist(
            id: "hero-preview",
            name: "Demo",
            kind: .xtream(host: host, username: "admin"),
            createdAt: Date(),
            isActive: true,
            expiresAt: expiry
        )
        return HomeAccount(playlist: playlist, now: Date())
    }
}
#endif
