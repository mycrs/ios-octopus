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
    @Published public private(set) var recentChannels: [Channel] = []
    @Published public private(set) var state: LoadableState<Int> = .idle

    public var isEmpty: Bool {
        resumeItems.isEmpty && recentlyAdded.isEmpty && recentChannels.isEmpty
    }

    /// Tepede dönen öne çıkan içerikler.
    @Published public private(set) var featured: [Movie] = []
    @Published public private(set) var featuredIndex = 0

    public var featuredItem: Movie? {
        guard featured.indices.contains(featuredIndex) else { return featured.first }
        return featured[featuredIndex]
    }

    private let dependencies: HomeDependencies
    private let shelfLimit: Int
    private let featuredLimit: Int
    private let featuredRotation: Duration
    private let now: () -> Date
    private var parentalFilter = ParentalFilter.open

    public init(
        dependencies: HomeDependencies,
        shelfLimit: Int = 12,
        // Beş yeterli: daha fazlası aynı içeriğe dönmeyi geciktirir ve
        // kullanıcı zaten üstteki tek karta bakıyor.
        featuredLimit: Int = 5,
        // Okumaya vakit bırakacak kadar uzun, sıkmayacak kadar kısa.
        featuredRotation: Duration = .seconds(8),
        now: @escaping () -> Date = Date.init
    ) {
        self.dependencies = dependencies
        self.shelfLimit = shelfLimit
        self.featuredLimit = featuredLimit
        self.featuredRotation = featuredRotation
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

    /// Kullanıcı sayfa noktalarına dokunarak doğrudan geçebilir.
    ///
    /// Dönen bir kartta "az önce gördüğüm şeye geri dön" ihtiyacı doğuyor;
    /// bir sonraki turu beklemek zorunda kalmasın.
    public func showFeatured(at index: Int) {
        guard featured.indices.contains(index) else { return }
        featuredIndex = index
    }

    /// Öne çıkan içeriği belirli aralıklarla değiştirir.
    ///
    /// Görünüm bunu `.task` içinde çağırır; ekrandan çıkılınca görev iptal
    /// edilir ve arka planda boşuna dönmez.
    public func rotateFeatured() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: featuredRotation)
            guard !Task.isCancelled, featured.count > 1 else { continue }
            featuredIndex = (featuredIndex + 1) % featured.count
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

            // Üç raf birbirinden bağımsız; paralel yüklenir.
            async let resume = loadResumeItems(playlistID: playlist.id)
            async let added = dependencies.vod.recentlyAdded(
                playlistID: playlist.id,
                limit: shelfLimit
            )
            async let channels = dependencies.history.recentChannels(
                playlistID: playlist.id,
                limit: shelfLimit
            )

            resumeItems = await resume
            recentlyAdded = parentalFilter.filter((try? await added) ?? [])
            recentChannels = parentalFilter.filter((try? await channels) ?? [])
            updateFeatured()

            state = .loaded(resumeItems.count + recentlyAdded.count + recentChannels.count)
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

    /// Öne çıkanları son eklenenlerden seçer.
    ///
    /// Görseli olanlar önce gelir: arka planı boş bir hero kartı, olmayan
    /// bir özelliği varmış gibi görünüp ekranı çirkinleştiriyor.
    private func updateFeatured() {
        let withArtwork = recentlyAdded.filter { $0.backdropURL != nil || $0.posterURL != nil }
        featured = Array(withArtwork.prefix(featuredLimit))

        // Liste kısaldıysa eldeki sıra taşabilir.
        if featuredIndex >= featured.count { featuredIndex = 0 }
    }

    private func clear() {
        resumeItems = []
        recentlyAdded = []
        recentChannels = []
        featured = []
        featuredIndex = 0
    }
}
