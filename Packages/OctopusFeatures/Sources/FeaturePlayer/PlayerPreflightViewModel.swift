import Foundation
import Combine
import OctopusDomain
import OctopusDesignSystem

/// Oynatıcı motoru gelene kadar zinciri doğrulayan ön kontrol.
///
/// Faz 5 gerçek cihaz gerektirdiği için oynatıcı boş duruyor. Ama
/// oynatıcıdan **önceki** her şey — kaynak, senkronizasyon, akış adresi
/// üretimi — şimdiden test edilebilir durumda. Bu ekran onu görünür kılar:
/// adres üretilebiliyorsa sorun oynatıcıda olacak, üretilemiyorsa sorun
/// zaten daha yukarıda.
///
/// Kullanıcı adresi kopyalayıp harici bir oynatıcıda deneyebilir; bu,
/// motor yazılmadan önce panelin gerçekten çalıştığını kanıtlar.
@MainActor
public final class PlayerPreflightViewModel: ObservableObject {

    public enum Outcome: Equatable {
        case checking
        case ready(PlaybackItem)
        case failed(String)
    }

    @Published public private(set) var outcome: Outcome = .checking

    private let dependencies: PlayerDependencies
    private let source: PlaybackItem.Source

    public init(dependencies: PlayerDependencies, source: PlaybackItem.Source) {
        self.dependencies = dependencies
        self.source = source
    }

    public func run() async {
        outcome = .checking

        do {
            outcome = .ready(try await resolveItem())
        } catch {
            outcome = .failed(AppError.wrap(error).userMessage)
        }
    }

    /// Kaynağa göre doğru depodan içeriği bulup akış adresini çözer.
    private func resolveItem() async throws -> PlaybackItem {
        switch source {
        case .liveChannel(let id):
            guard let channel = try await dependencies.channels.channel(id: id) else {
                throw AppError.notFound
            }
            return try await dependencies.streams.playbackItem(for: channel)

        case .movie(let id):
            guard let movie = try await dependencies.vod.movie(id: id) else {
                throw AppError.notFound
            }
            return try await dependencies.streams.playbackItem(for: movie)

        case .episode(let id):
            guard let episode = try await dependencies.series.episode(id: id) else {
                throw AppError.notFound
            }
            guard let series = try await dependencies.series.series(id: episode.seriesID) else {
                throw AppError.notFound
            }
            return try await dependencies.streams.playbackItem(for: episode, in: series)
        }
    }

    // MARK: - Sunum

    /// ⚠️ ASCII olmalı: `URLComponents` adrese yazarken ASCII dışını
    /// yüzde-kodlar; "•••" ekranda `%E2%80%A2…` diye okunmaz hâle gelirdi.
    private static let mask = "***"

    private static let sensitiveQueryKeys: Set<String> = [
        "username", "password", "token", "user", "pass"
    ]

    /// Ekranda gösterilecek adres — **kimlik bilgileri maskeli**.
    ///
    /// ⚠️ Xtream adresleri kullanıcı adını ve parolayı yol içinde taşır:
    /// `http://sunucu:8080/kullanıcı/parola/12345.ts`
    /// Ham hâlini ekrana basmak, bir ekran görüntüsü paylaşıldığında
    /// hesabın ele geçmesi demek. Kopyalanan değer tam adrestir.
    public static func maskedURL(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }

        components.queryItems = components.queryItems?.map { item in
            guard sensitiveQueryKeys.contains(item.name.lowercased()) else { return item }
            return URLQueryItem(name: item.name, value: mask)
        }

        // Xtream'de kimlik yolun kendisindedir: /<kullanıcı>/<parola>/<id>.<uzantı>
        // Baştaki "/" boş bir parça üretir, bu yüzden kimlik 1 ve 2. sıradadır.
        var segments = components.path
            .split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)

        if segments.count >= 4 {
            segments[1] = mask
            segments[2] = mask
            components.path = segments.joined(separator: "/")
        }

        return components.url?.absoluteString ?? url.absoluteString
    }
}
