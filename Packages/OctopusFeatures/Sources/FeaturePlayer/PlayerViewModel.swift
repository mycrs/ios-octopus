import Foundation
import Combine
import OctopusDomain
import OctopusDesignSystem

/// Oynatıcının **hazırlık** aşaması: içerikten oynatılabilir adrese.
///
/// Oynatmanın kendisi `PlayerController`'ın (OctopusPlayback) işi. Burada
/// yalnızca "hangi içerik, hangi adres" sorusu cevaplanır — bu soru
/// repository'lere bağlı olduğu için feature katmanında kalır.
///
/// Ayrım pratikte şunu sağlıyor: adres üretilemediğinde hata **oynatıcıya
/// hiç girmeden** gösterilir ve kullanıcı adresi kopyalayıp harici bir
/// oynatıcıda deneyebilir. Sorunun kaynakta mı motorda mı olduğu böylece
/// tek bakışta ayrılır.
@MainActor
public final class PlayerViewModel: ObservableObject {

    public enum Phase: Equatable {
        case resolving
        case ready(PlaybackItem)
        case failed(String)
    }

    @Published public private(set) var phase: Phase = .resolving

    /// Canlı yayında kanal değiştirilebilir mi? (Liste tek kanaldan ibaretse hayır.)
    @Published public private(set) var canZap = false

    private let dependencies: PlayerDependencies

    /// Şu an oynayan kaynak — zaplama bunu değiştirir.
    private var source: PlaybackItem.Source

    /// Zaplama sırası. **Ebeveyn kilidiyle süzülmüş** hâli tutulur.
    private var zapList: [Channel] = []

    public init(dependencies: PlayerDependencies, source: PlaybackItem.Source) {
        self.dependencies = dependencies
        self.source = source
    }

    public func resolve() async {
        phase = .resolving
        do {
            phase = .ready(try await resolveItem())
            await prepareZapping()
        } catch {
            phase = .failed(AppError.wrap(error).userMessage)
        }
    }

    // MARK: - Kanal değiştirme

    /// Canlı yayında sonraki/önceki kanal için listeyi hazırlar.
    ///
    /// ⚠️ Liste **kilitle süzülür**. Süzülmezse kullanıcı zaplayarak
    /// yetişkin bir kanala düşebilir ve kilit bu yoldan atlatılmış olur
    /// (bkz. BRAIN.md — kilit tek yerde tutulur, **yedi** yerde uygulanır).
    private func prepareZapping() async {
        guard case .liveChannel(let id) = source else {
            zapList = []
            canZap = false
            return
        }

        guard let current = try? await dependencies.channels.channel(id: id) else { return }

        let filter = await ParentalFilter.current(dependencies.parental)
        let all = (try? await dependencies.channels.channels(
            playlistID: current.playlistID,
            categoryID: nil
        )) ?? []

        zapList = filter.filter(all)
        canZap = zapList.count > 1
    }

    /// Listede verilen adım kadar ilerler ve o kanalı açar.
    ///
    /// Liste **döngüsel**: son kanaldan sonra başa döner. IPTV
    /// kumandalarının alışılmış davranışı bu; sınırda durmak
    /// "bozuk mu?" hissi veriyor.
    public func zap(by step: Int) async {
        guard
            case .liveChannel(let id) = source,
            let index = zapList.firstIndex(where: { $0.id == id }),
            !zapList.isEmpty
        else { return }

        let count = zapList.count
        // Swift'te `%` negatif değer üretebilir; `+ count` ile toparlanır.
        let target = ((index + step) % count + count) % count

        source = .liveChannel(zapList[target].id)

        do {
            phase = .ready(try await resolveItem())
        } catch {
            phase = .failed(AppError.wrap(error).userMessage)
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

    /// Saniyeyi `s:dd` / `sa:dd:ss` biçimine çevirir.
    ///
    /// ⚠️ `DateComponentsFormatter` burada kullanılmıyor: canlı yayında
    /// süre `nil` ve bilinmeyen değerler için "--:--" göstermek gerekiyor;
    /// formatter bu durumda boş dizgi döndürüp çubuğu bozuyordu.
    public static func timeLabel(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "--:--" }

        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60

        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
