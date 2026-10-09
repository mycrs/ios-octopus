import Foundation

/// Sağlayıcının doğrulanmış hesap durumu. Bilinmeyen/eski kayıtta nil tutulur.
public enum SubscriptionStatus: String, Hashable, Codable, Sendable {
    case active, expired, inactive, disabled, banned
}

/// Erişim reddinin güvenli metadata'sı; hesap bilgisi veya adres içermez.
public struct SubscriptionAccessBlock: Hashable, Codable, Sendable {
    public let status: SubscriptionStatus
    public let expiresAt: Date?

    public init(status: SubscriptionStatus, expiresAt: Date?) {
        self.status = status
        self.expiresAt = expiresAt
    }

    public static func evaluate(
        status: SubscriptionStatus?, expiresAt: Date?, at date: Date
    ) -> Self? {
        if let status, status != .active {
            return Self(status: status, expiresAt: expiresAt)
        }
        if let expiresAt, expiresAt <= date {
            return Self(status: .expired, expiresAt: expiresAt)
        }
        return nil
    }
}

extension Playlist {
    /// Gün sayısı yuvarlaması erişim kararı değildir; gerçek sınır anı kullanılır.
    public func subscriptionBlock(at date: Date) -> SubscriptionAccessBlock? {
        SubscriptionAccessBlock.evaluate(
            status: subscriptionStatus, expiresAt: expiresAt, at: date
        )
    }
}

extension ProviderAccount {
    public func subscriptionBlock(at date: Date) -> SubscriptionAccessBlock? {
        SubscriptionAccessBlock.evaluate(
            status: subscriptionStatus, expiresAt: expiresAt, at: date
        )
    }
}
