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
        current ? Haptics.success() : Haptics.light()
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

    /// Künye çipleri: puan, yıl, süre, tür.
    ///
    /// Tek uzun satır yerine ayrı çipler — uzun tür listelerinde satır
    /// taşması yerine yatay kaydırma olur ve göz bilgileri ayırt eder.
    public var chips: [DetailChip] {
        guard let movie else { return [] }
        var result: [DetailChip] = []

        if let rating = movie.rating, rating > 0 {
            result.append(
                DetailChip(
                    text: String(format: "%.1f", rating),
                    icon: "star.fill",
                    isHighlighted: true
                )
            )
        }
        if let year = Self.year(of: movie.releaseDate) {
            result.append(DetailChip(text: year, icon: "calendar"))
        }
        if let duration = Self.durationText(movie.durationSeconds) {
            result.append(DetailChip(text: duration, icon: "clock"))
        }
        // İlk üç tür yeter; sağlayıcılar bazen on beş tür yazıyor.
        for genre in movie.genres.prefix(3) where !genre.isEmpty {
            result.append(DetailChip(text: genre))
        }

        return result
    }

    static func year(of date: Date?) -> String? {
        guard let date else { return nil }
        // Sabit takvim ve UTC: cihaz saat dilimi yılı kaydırmasın.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return String(calendar.component(.year, from: date))
    }

    static func durationText(_ seconds: Int?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        return hours > 0 ? "\(hours)s \(minutes)dk" : "\(minutes)dk"
    }

}
