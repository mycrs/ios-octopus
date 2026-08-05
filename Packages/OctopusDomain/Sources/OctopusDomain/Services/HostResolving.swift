import Foundation

/// Ölü sunucuda yedek adrese geçiş.
///
/// IPTV sağlayıcıları sunucu adreslerini sık değiştirir; eski adres bir gün
/// yanıt vermemeye başlar. Kullanıcı bunu "uygulama bozuldu" diye yaşar.
/// Panel yedek adres listesi tutar; bu protokol çalışan ilkini bulur.
public protocol HostResolving: Sendable {

    /// - Parameter current: Kaynağa kayıtlı adres.
    /// - Returns: Çalışan adres. Hiçbiri yanıt vermezse `current` döner —
    ///   böylece hata mesajı kullanıcının tanıdığı adresi gösterir.
    func resolve(preferring current: URL) async -> URL
}

/// Failover devre dışı — adres olduğu gibi kullanılır.
public struct PassthroughHostResolver: HostResolving {
    public init() {}
    public func resolve(preferring current: URL) async -> URL { current }
}
