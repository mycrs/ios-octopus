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
    /// Yönlendirmeden gelen açık başlangıç konumu, kayıtlı ilerlemeyi ezer.
    private let startAt: TimeInterval?

    /// Şu an oynayan kaynak — zaplama bunu değiştirir.
    private var source: PlaybackItem.Source

    /// Zaplama sırası. **Ebeveyn kilidiyle süzülmüş** hâli tutulur.
    private var zapList: [Channel] = []

    public init(
        dependencies: PlayerDependencies,
        source: PlaybackItem.Source,
        startAt: TimeInterval? = nil
    ) {
        self.dependencies = dependencies
        self.source = source
        self.startAt = startAt
    }

    public func resolve() async {
        phase = .resolving
        do {
            phase = .ready(applyingStartPosition(to: try await resolveItem()))
            await prepareZapping()
        } catch {
            phase = .failed(AppError.wrap(error).userMessage)
        }
    }

    private func applyingStartPosition(to item: PlaybackItem) -> PlaybackItem {
        guard
            !item.isLive,
            let startAt,
            startAt.isFinite,
            startAt >= 0
        else { return item }

        return item.resuming(at: startAt)
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

}
