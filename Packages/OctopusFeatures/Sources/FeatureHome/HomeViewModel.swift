import Foundation
import Combine
import OctopusDomain
import OctopusDesignSystem

/// Ana sayfa rafları: izlemeye devam et, son eklenenler, son izlenen kanallar.
@MainActor
public final class HomeViewModel: ObservableObject {

    /// "İzlemeye devam et" rafındaki tek öğe.
    ///
    /// Film ve bölüm aynı rafta gösterildiği için ortak bir sunum tipi
    /// kullanılır; ekran hangi tür olduğunu bilmek zorunda kalmaz.
    public struct ResumeItem: Identifiable, Equatable {
        public let id: String
        public let title: String
        public let subtitle: String?
        public let posterURL: URL?
        public let fraction: Double
        public let source: PlaybackItem.Source
    }

    @Published public private(set) var resumeItems: [ResumeItem] = []
    @Published public private(set) var recentlyAdded: [Movie] = []
    /// Son eklenen diziler — filmlerin altındaki raf.
    @Published public private(set) var recentSeries: [Series] = []

    /// Hero'daki hesap satırı: kullanıcı adı ve aboneliğe kalan gün.
    ///
    /// Referans uygulamada bu bilgi kocaman bir mor kartın içinde iki
    /// kutuya bölünmüştü. Burada tek satır: iOS'ta ikincil bilgi sessiz
    /// durur, yalnızca **acil olduğunda** (abonelik bitmek üzere) renk alır.
    @Published public private(set) var account: HomeAccount?
    @Published public private(set) var recentChannels: [Channel] = []
    @Published public private(set) var state: LoadableState<Int> = .idle

    public var isEmpty: Bool {
        resumeItems.isEmpty && recentlyAdded.isEmpty
            && recentSeries.isEmpty && recentChannels.isEmpty
    }


    private let dependencies: HomeDependencies
    private let shelfLimit: Int
    private let now: () -> Date
    private var parentalFilter = ParentalFilter.open

    public init(
        dependencies: HomeDependencies,
        shelfLimit: Int = 12,
        now: @escaping () -> Date = Date.init
    ) {
        self.dependencies = dependencies
        self.shelfLimit = shelfLimit
        self.now = now
    }

    /// Saate göre karşılama — Android sürümüyle aynı davranış.
    public var greeting: String {
        switch Calendar.current.component(.hour, from: now()) {
        case 5..<12: return "Günaydın"
        case 12..<18: return "İyi günler"
        case 18..<22: return "İyi akşamlar"
        default: return "İyi geceler"
        }
    }


    public func load() async {
        if isEmpty { state = .loading }

        do {
            guard let playlist = try await dependencies.playlists.activePlaylist() else {
                state = .loaded(0)
                clear()
                return
            }

            // Raflar süzülmeden önce kilit durumu bilinmeli.
            parentalFilter = await .current(dependencies.parental)
            account = HomeAccount(playlist: playlist, now: Date())

            // Raflar birbirinden bağımsız; paralel yüklenir.
            async let resume = loadResumeItems(playlistID: playlist.id)
            async let added = dependencies.vod.recentlyAdded(
                playlistID: playlist.id,
                limit: shelfLimit
            )
            async let series = dependencies.series.recentlyAdded(
                playlistID: playlist.id,
                limit: shelfLimit
            )
            async let channels = dependencies.history.recentChannels(
                playlistID: playlist.id,
                limit: shelfLimit
            )

            resumeItems = await resume
            recentlyAdded = parentalFilter.filter((try? await added) ?? [])
            // ⚠️ Diziler de süzülür: kilit yalnızca filmlerde uygulansaydı
            // yetişkin bir dizi ana sayfada afişiyle durmaya devam ederdi.
            recentSeries = parentalFilter.filter((try? await series) ?? [])
            recentChannels = parentalFilter.filter((try? await channels) ?? [])

            state = .loaded(
                resumeItems.count + recentlyAdded.count
                    + recentSeries.count + recentChannels.count
            )
        } catch {
            state = .failed(AppError.wrap(error))
        }
    }

    /// İlerleme kayıtlarını gerçek içeriğe bağlar.
    ///
    /// Kayıtlar yalnızca anahtar taşır; başlık ve afiş için katalog
    /// depolarına sorulur. Silinmiş içeriğin kaydı sessizce atlanır —
    /// kullanıcı artık var olmayan bir filme tıklayamamalı.
    private func loadResumeItems(playlistID: Playlist.ID) async -> [ResumeItem] {
        guard let stored = try? await dependencies.progress.continueWatching(
            playlistID: playlistID,
            limit: shelfLimit
        ) else { return [] }

        var items: [ResumeItem] = []

        for progress in stored {
            guard let source = PlaybackItem.Source(storageKey: progress.itemKey) else { continue }

            switch source {
            case .movie(let id):
                guard let movie = try? await dependencies.vod.movie(id: id),
                      parentalFilter.allows(movie: movie)
                else { continue }
                items.append(
                    ResumeItem(
                        id: progress.itemKey,
                        title: movie.title,
                        subtitle: nil,
                        posterURL: movie.posterURL,
                        fraction: progress.fraction,
                        source: source
                    )
                )

            case .episode(let id):
                guard let episode = try? await dependencies.series.episode(id: id) else { continue }
                let series = try? await dependencies.series.series(id: episode.seriesID)
                items.append(
                    ResumeItem(
                        id: progress.itemKey,
                        title: series?.title ?? episode.title,
                        subtitle: episode.shortLabel,
                        posterURL: series?.posterURL ?? episode.stillURL,
                        fraction: progress.fraction,
                        source: source
                    )
                )

            case .liveChannel:
                // Canlı yayında "kaldığın yer" kavramı yok.
                continue
            }
        }

        return items
    }

    private func clear() {
        account = nil
        resumeItems = []
        recentlyAdded = []
        recentSeries = []
        recentChannels = []
    }
}
