import Foundation
import Combine
import OctopusDomain
import OctopusDesignSystem

/// Film detayı: künye, favori, kaldığı yerden devam.
@MainActor
public final class MovieDetailViewModel: ObservableObject {

    @Published public private(set) var movie: Movie?
    @Published public private(set) var state: LoadableState<Bool> = .idle
    @Published public private(set) var isFavorite = false
    /// Yarım bırakıldıysa izlenme oranı (0...1).
    @Published public private(set) var resumeFraction: Double?

    private let movieID: Movie.ID
    private let dependencies: VODDependencies

    public init(movieID: Movie.ID, dependencies: VODDependencies) {
        self.movieID = movieID
        self.dependencies = dependencies
    }

    public func load() async {
        state = .loading

        do {
            // Künye önbellekli: ilk açılışta çekilir, sonra yerelden okunur.
            let loaded = try await dependencies.vod.loadDetails(id: movieID)
            movie = loaded
            isFavorite = (try? await dependencies.favorites.isFavorite(.movie(movieID))) ?? false
            await refreshProgress()
            state = .loaded(true)
        } catch {
            state = .failed(AppError.wrap(error))
        }
    }

    private func refreshProgress() async {
        guard let stored = try? await dependencies.progress.progress(for: .movie(movieID)),
              !stored.isFinished,
              stored.fraction > 0.01
        else {
            resumeFraction = nil
            return
        }
        resumeFraction = stored.fraction
    }

    public func toggleFavorite() async {
        guard let current = try? await dependencies.favorites.toggle(.movie(movieID)) else {
            return
        }
        isFavorite = current
    }

    /// İzleme kaydını siler — kullanıcı baştan başlamak isteyebilir.
    public func resetProgress() async {
        try? await dependencies.progress.clear(for: .movie(movieID))
        resumeFraction = nil
    }

    // MARK: - Sunum yardımcıları

    /// Oynat düğmesinin etiketi.
    public var playButtonTitle: String {
        resumeFraction == nil ? "Oynat" : "Devam et"
    }

    /// "2020 · 1s 47dk" biçiminde künye satırı.
    public var metadataLine: String? {
        guard let movie else { return nil }
        var parts: [String] = []

        if let releaseDate = movie.releaseDate {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
            parts.append(String(calendar.component(.year, from: releaseDate)))
        }
        if let seconds = movie.durationSeconds, seconds > 0 {
            let hours = seconds / 3_600
            let minutes = (seconds % 3_600) / 60
            parts.append(hours > 0 ? "\(hours)s \(minutes)dk" : "\(minutes)dk")
        }
        if !movie.genres.isEmpty {
            parts.append(movie.genres.prefix(2).joined(separator: ", "))
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
