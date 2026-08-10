import Foundation

extension PlayerViewModel {

    /// ASCII kalmalı: URLComponents maske işaretini yüzde-kodlamasın.
    private static var mask: String { "***" }

    private static var sensitiveQueryKeys: Set<String> {
        ["username", "password", "token", "user", "pass"]
    }

    /// Ekranda gösterilecek adres; Xtream kimlik bilgileri maskelenir.
    public static func maskedURL(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }

        components.queryItems = components.queryItems?.map { item in
            guard sensitiveQueryKeys.contains(item.name.lowercased()) else { return item }
            return URLQueryItem(name: item.name, value: mask)
        }

        var segments = components.path
            .split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)

        // Xtream: /<kullanıcı>/<parola>/<id>.<uzantı>
        if segments.count >= 4 {
            segments[1] = mask
            segments[2] = mask
            components.path = segments.joined(separator: "/")
        }

        return components.url?.absoluteString ?? url.absoluteString
    }

    /// Saniyeyi `d:dd` / `sa:dd:ss` biçimine çevirir.
    public static func timeLabel(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "--:--" }

        let total = Int(seconds.rounded())
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let secs = total % 60

        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
