import Foundation
import OctopusDomain

/// Kullanıcının açıkça eklediği örnek kaynak. Katalog/rehber yereldir;
/// medya yalnızca kullanıcı oynatmayı başlatınca lisanslı aynadan açılır.
public struct SampleLibraryContentProvider: ContentProvider {
    private let playlistID: Playlist.ID
    private static let collectionKey = "open-film-collection"

    public init(playlistID: Playlist.ID) { self.playlistID = playlistID }

    public var streamHeaders: [String: String] { [:] }
    public var epgSourceURL: URL? { nil }

    public func authenticate() async throws -> ProviderAccount {
        guard !SampleLibraryCatalog.credits.isEmpty else {
            throw AppError.invalidResponse(reason: "Örnek kitaplık hazırlanamadı")
        }
        return ProviderAccount(username: "Örnek", expiresAt: nil, isTrial: false,
                               maxConnections: 1, activeConnections: 0)
    }

    public func fetchCategories(kind: MediaCategory.Kind) async throws -> [MediaCategory] {
        let name: String
        switch kind {
        case .live: name = "Örnek / Sample Channels"
        case .movie: name = "Açık Filmler / Open Films"
        case .series: name = "Örnek / Sample Film Collection"
        }
        return [MediaCategory(id: categoryID(kind), playlistID: playlistID, kind: kind, name: name)]
    }

    public func fetchChannels(categoryID: MediaCategory.ID?) async throws -> [Channel] {
        guard categoryID == nil || categoryID == self.categoryID(.live) else { return [] }
        return SampleLibraryCatalog.credits.enumerated().map { index, film in
            Channel(
                id: EntityID.channel(playlistID: playlistID, rawID: film.id),
                playlistID: playlistID, name: "Örnek / Sample · \(film.title)",
                streamKey: film.id, logoURL: film.artworkURL, categoryID: self.categoryID(.live),
                epgChannelID: "sample.\(film.id)", number: index + 1, sortOrder: index
            )
        }
    }

    public func fetchMovies(categoryID: MediaCategory.ID?) async throws -> [Movie] {
        guard categoryID == nil || categoryID == self.categoryID(.movie) else { return [] }
        return SampleLibraryCatalog.credits.enumerated().map { index, film in
            movie(film, index: index)
        }
    }

    public func fetchMovieDetails(streamKey: String) async throws -> Movie {
        guard let index = SampleLibraryCatalog.credits.firstIndex(where: { $0.id == streamKey }) else {
            throw AppError.notFound
        }
        return movie(SampleLibraryCatalog.credits[index], index: index)
    }

    public func fetchSeries(categoryID: MediaCategory.ID?) async throws -> [Series] {
        guard categoryID == nil || categoryID == self.categoryID(.series) else { return [] }
        return [Series(
            id: collectionID, playlistID: playlistID,
            title: SampleLibraryCatalog.collectionTitle, streamKey: Self.collectionKey,
            posterURL: SampleLibraryCatalog.credits.first?.artworkURL,
            categoryID: self.categoryID(.series),
            plot: "Sample collection of independent open films, played in full with their original closing credits. This is a film collection, not a TV series.\nBu örnek seçki bağımsız açık filmleri özgün kapanış jenerikleriyle bütünüyle oynatır; bir televizyon dizisi değildir.",
            genres: ["Örnek / Sample", "Açık Film / Open Film"]
        )]
    }

    public func fetchSeriesDetails(streamKey: String) async throws -> (seasons: [Season], episodes: [Episode]) {
        guard streamKey == Self.collectionKey else { throw AppError.notFound }
        let episodes = SampleLibraryCatalog.credits.enumerated().map { index, film in
            Episode(
                id: EntityID.episode(seriesID: collectionID, rawID: film.id),
                seriesID: collectionID, seasonNumber: 1, number: index + 1,
                title: film.title, streamKey: film.id, containerExtension: "mp4",
                plot: attribution(film), durationSeconds: film.durationSeconds
            )
        }
        return (
            [Season(id: EntityID.season(seriesID: collectionID, number: 1), seriesID: collectionID,
                    number: 1, name: "Açık Filmler / Open Films", episodeCount: episodes.count)],
            episodes
        )
    }

    public func streamURL(for channel: Channel) -> URL? {
        guard channel.playlistID == playlistID else { return nil }
        return videoURL(channel.streamKey)
    }

    public func streamURL(for movie: Movie) -> URL? {
        guard movie.playlistID == playlistID else { return nil }
        return videoURL(movie.streamKey)
    }

    public func streamURL(for episode: Episode) -> URL? {
        guard episode.seriesID == collectionID else { return nil }
        return videoURL(episode.streamKey)
    }

    public func localEPGPrograms(at date: Date) -> [EPGProgram]? {
        let slotLength: TimeInterval = 30 * 60
        let slotStart = Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 / slotLength) * slotLength)
        return SampleLibraryCatalog.credits.flatMap { film in
            (0..<3).map { slot in
                let start = slotStart.addingTimeInterval(Double(slot) * slotLength)
                let channelID = "sample.\(film.id)"
                return EPGProgram(
                    id: EntityID.epgProgram(epgChannelID: channelID, startDate: start),
                    epgChannelID: channelID, title: "Örnek / Sample Guide · \(film.title)",
                    summary: "Local sample guide. This channel plays a recorded film; these sample times do not represent a real live broadcast schedule.\nBu rehber yerel bir örnektir. Kanal kayıtlı bir filmi oynatır; gerçek canlı yayın veya yayın takvimi değildir.",
                    startDate: start, endDate: start.addingTimeInterval(slotLength)
                )
            }
        }
    }

    private var collectionID: Series.ID { EntityID.series(playlistID: playlistID, rawID: Self.collectionKey) }

    private func categoryID(_ kind: MediaCategory.Kind) -> MediaCategory.ID {
        EntityID.category(playlistID: playlistID, kind: kind, rawID: "sample")
    }

    private func videoURL(_ streamKey: String) -> URL? {
        SampleLibraryCatalog.credits.first { $0.id == streamKey }?.videoURL
    }

    private func movie(_ film: SampleLibraryCredit, index: Int) -> Movie {
        Movie(
            id: EntityID.movie(playlistID: playlistID, rawID: film.id), playlistID: playlistID,
            title: film.title, streamKey: film.id, containerExtension: "mp4",
            posterURL: film.artworkURL,
            categoryID: categoryID(.movie), plot: attribution(film),
            durationSeconds: film.durationSeconds, genres: ["Animasyon / Animation", "Açık Film / Open Film"], sortOrder: index
        )
    }

    private func attribution(_ film: SampleLibraryCredit) -> String {
        "\(film.copyrightNotice)\n\(film.licenseName)\nOpen film from the sample library, with the full original closing credits.\nBu açık film örnek kitaplığın parçasıdır. Tam kapanış jenerikleri korunur."
    }
}
