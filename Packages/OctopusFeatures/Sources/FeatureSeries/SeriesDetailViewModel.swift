import Foundation
import Combine
import OctopusDomain
import OctopusDesignSystem

/// Dizi detayı: sezon seçimi ve bölüm listesi.
@MainActor
public final class SeriesDetailViewModel: ObservableObject {

    @Published public private(set) var series: Series?
    @Published public private(set) var seasons: [Season] = []
    @Published public private(set) var episodes: [Episode] = []
    @Published public private(set) var selectedSeasonNumber: Int?
    @Published public private(set) var state: LoadableState<Int> = .idle
    @Published public private(set) var isFavorite = false

    /// Bölüm kimliğine göre izleme oranı (0...1).
    @Published public private(set) var watchedFraction: [String: Double] = [:]

    private let seriesID: Series.ID
    private let dependencies: SeriesDependencies

    public init(seriesID: Series.ID, dependencies: SeriesDependencies) {
        self.seriesID = seriesID
        self.dependencies = dependencies
    }

    // MARK: - Yükleme

    public func load() async {
        state = .loading

        do {
            guard let found = try await dependencies.series.series(id: seriesID) else {
                state = .failed(.notFound)
                return
            }
            series = found
            isFavorite = (try? await dependencies.favorites.isFavorite(.series(seriesID))) ?? false

            // Ağaç yerelde varsa istek atılmaz; yoksa sağlayıcıdan çekilir.
            try await dependencies.series.loadDetails(id: seriesID)

            seasons = try await dependencies.series.seasons(seriesID: seriesID)
            // İlk sezon otomatik seçilir: kullanıcı boş ekranla karşılaşmamalı.
            let firstSeason = seasons.first?.number
            selectedSeasonNumber = firstSeason

            if let firstSeason {
                await loadEpisodes(seasonNumber: firstSeason)
            } else {
                episodes = []
                state = .loaded(0)
            }
        } catch {
            state = .failed(AppError.wrap(error))
        }
    }

    public func selectSeason(_ number: Int) async {
        guard selectedSeasonNumber != number else { return }
        selectedSeasonNumber = number
        await loadEpisodes(seasonNumber: number)
    }

    private func loadEpisodes(seasonNumber: Int) async {
        do {
            let loaded = try await dependencies.series.episodes(
                seriesID: seriesID,
                seasonNumber: seasonNumber
            )
            episodes = loaded
            state = .loaded(loaded.count)
            await refreshProgress(for: loaded)
        } catch {
            state = .failed(AppError.wrap(error))
        }
    }

    /// İzlenen bölümleri işaretlemek için ilerleme bilgisini toplar.
    private func refreshProgress(for episodes: [Episode]) async {
        var fractions: [String: Double] = [:]
        for episode in episodes {
            if let stored = try? await dependencies.progress.progress(for: .episode(episode.id)),
               stored.fraction > 0.01 {
                fractions[episode.id.value] = stored.fraction
            }
        }
        watchedFraction = fractions
    }

    // MARK: - Eylemler

    public func toggleFavorite() async {
        guard let current = try? await dependencies.favorites.toggle(.series(seriesID)) else {
            return
        }
        isFavorite = current
    }

    /// Kullanıcı "yenile" derse ağaç yeniden çekilir.
    ///
    /// Panelde yeni bölüm yayınlanmış olabilir ve önbellek onu göstermez.
    public func refresh() async {
        try? await dependencies.series.invalidateDetails(id: seriesID)
        await load()
    }

    /// Kaldığı yerden devam edilecek ilk bölüm.
    ///
    /// Yarım bırakılmış bölüm varsa o, yoksa hiç izlenmemiş ilk bölüm.
    public var resumeEpisode: Episode? {
        if let partial = episodes.first(where: {
            let fraction = watchedFraction[$0.id.value] ?? 0
            return fraction > 0.01 && fraction < 0.95
        }) {
            return partial
        }
        return episodes.first { (watchedFraction[$0.id.value] ?? 0) < 0.95 }
    }

    public func isWatched(_ episode: Episode) -> Bool {
        (watchedFraction[episode.id.value] ?? 0) >= 0.95
    }

    public func progress(for episode: Episode) -> Double? {
        guard let fraction = watchedFraction[episode.id.value],
              fraction > 0.01, fraction < 0.95
        else { return nil }
        return fraction
    }
}
