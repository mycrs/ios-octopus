import Foundation
import GRDB
import OctopusDomain

/// Dizi alanlarını (tür, oyuncu) tek kolonda saklamak için basit JSON kodlaması.
///
/// Bu alanlarda sorgu yapılmıyor — ayrı tablo açmak gereksiz karmaşıklık olurdu.
/// Bozuk veri hâlinde boş dizi döner: eksik tür listesi yüzünden film kartının
/// hiç açılmaması kabul edilebilir bir davranış değil.
enum StringListColumn {

    static func encode(_ values: [String]) -> String {
        guard !values.isEmpty,
              let data = try? JSONEncoder().encode(values),
              let json = String(data: data, encoding: .utf8)
        else { return "[]" }
        return json
    }

    static func decode(_ raw: String) -> [String] {
        guard let data = raw.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return values
    }
}

// MARK: - Film

struct MovieRecord: Codable, FetchableRecord, PersistableRecord {

    static let databaseTableName = "movie"

    var id: String
    var playlistId: String
    var title: String
    var streamKey: String
    var containerExtension: String?
    var posterURL: String?
    var backdropURL: String?
    var categoryId: String?
    var plot: String?
    var releaseDate: Date?
    var durationSeconds: Int?
    var rating: Double?
    var genres: String
    var cast: String
    var director: String?
    var isAdult: Bool
    var addedAt: Date?
    /// Detay (özet, oyuncular) çekildiyse zaman damgası — tekrar çekmemek için.
    var detailsLoadedAt: Date?

    init(_ movie: Movie, detailsLoadedAt: Date? = nil) {
        self.id = movie.id.value
        self.playlistId = movie.playlistID.value
        self.title = movie.title
        self.streamKey = movie.streamKey
        self.containerExtension = movie.containerExtension
        self.posterURL = movie.posterURL?.absoluteString
        self.backdropURL = movie.backdropURL?.absoluteString
        self.categoryId = movie.categoryID?.value
        self.plot = movie.plot
        self.releaseDate = movie.releaseDate
        self.durationSeconds = movie.durationSeconds
        self.rating = movie.rating
        self.genres = StringListColumn.encode(movie.genres)
        self.cast = StringListColumn.encode(movie.cast)
        self.director = movie.director
        self.isAdult = movie.isAdult
        self.addedAt = movie.addedAt
        self.detailsLoadedAt = detailsLoadedAt
    }

    func toDomain() -> Movie {
        Movie(
            id: Movie.ID(id),
            playlistID: Playlist.ID(playlistId),
            title: title,
            streamKey: streamKey,
            containerExtension: containerExtension,
            posterURL: posterURL.flatMap { URL(string: $0) },
            backdropURL: backdropURL.flatMap { URL(string: $0) },
            categoryID: categoryId.map { MediaCategory.ID($0) },
            plot: plot,
            releaseDate: releaseDate,
            durationSeconds: durationSeconds,
            rating: rating,
            genres: StringListColumn.decode(genres),
            cast: StringListColumn.decode(cast),
            director: director,
            isAdult: isAdult,
            addedAt: addedAt
        )
    }
}

// MARK: - Dizi

struct SeriesRecord: Codable, FetchableRecord, PersistableRecord {

    static let databaseTableName = "series"

    var id: String
    var playlistId: String
    var title: String
    var streamKey: String
    var posterURL: String?
    var backdropURL: String?
    var categoryId: String?
    var plot: String?
    var rating: Double?
    var genres: String
    var cast: String
    var releaseDate: Date?
    var lastModified: Date?
    var isAdult: Bool
    var detailsLoadedAt: Date?

    init(_ series: Series, detailsLoadedAt: Date? = nil) {
        self.id = series.id.value
        self.playlistId = series.playlistID.value
        self.title = series.title
        self.streamKey = series.streamKey
        self.posterURL = series.posterURL?.absoluteString
        self.backdropURL = series.backdropURL?.absoluteString
        self.categoryId = series.categoryID?.value
        self.plot = series.plot
        self.rating = series.rating
        self.genres = StringListColumn.encode(series.genres)
        self.cast = StringListColumn.encode(series.cast)
        self.releaseDate = series.releaseDate
        self.lastModified = series.lastModified
        self.isAdult = series.isAdult
        self.detailsLoadedAt = detailsLoadedAt
    }

    func toDomain() -> Series {
        Series(
            id: Series.ID(id),
            playlistID: Playlist.ID(playlistId),
            title: title,
            streamKey: streamKey,
            posterURL: posterURL.flatMap { URL(string: $0) },
            backdropURL: backdropURL.flatMap { URL(string: $0) },
            categoryID: categoryId.map { MediaCategory.ID($0) },
            plot: plot,
            rating: rating,
            genres: StringListColumn.decode(genres),
            cast: StringListColumn.decode(cast),
            releaseDate: releaseDate,
            lastModified: lastModified,
            isAdult: isAdult
        )
    }
}

// MARK: - Sezon

struct SeasonRecord: Codable, FetchableRecord, PersistableRecord {

    static let databaseTableName = "season"

    var id: String
    var seriesId: String
    var number: Int
    var name: String?
    var posterURL: String?
    var episodeCount: Int

    init(_ season: Season) {
        self.id = season.id.value
        self.seriesId = season.seriesID.value
        self.number = season.number
        self.name = season.name
        self.posterURL = season.posterURL?.absoluteString
        self.episodeCount = season.episodeCount
    }

    func toDomain() -> Season {
        Season(
            id: Season.ID(id),
            seriesID: Series.ID(seriesId),
            number: number,
            name: name,
            posterURL: posterURL.flatMap { URL(string: $0) },
            episodeCount: episodeCount
        )
    }
}

// MARK: - Bölüm

struct EpisodeRecord: Codable, FetchableRecord, PersistableRecord {

    static let databaseTableName = "episode"

    var id: String
    var seriesId: String
    var seasonNumber: Int
    var number: Int
    var title: String
    var streamKey: String
    var containerExtension: String?
    var plot: String?
    var stillURL: String?
    var durationSeconds: Int?
    var airDate: Date?

    init(_ episode: Episode) {
        self.id = episode.id.value
        self.seriesId = episode.seriesID.value
        self.seasonNumber = episode.seasonNumber
        self.number = episode.number
        self.title = episode.title
        self.streamKey = episode.streamKey
        self.containerExtension = episode.containerExtension
        self.plot = episode.plot
        self.stillURL = episode.stillURL?.absoluteString
        self.durationSeconds = episode.durationSeconds
        self.airDate = episode.airDate
    }

    func toDomain() -> Episode {
        Episode(
            id: Episode.ID(id),
            seriesID: Series.ID(seriesId),
            seasonNumber: seasonNumber,
            number: number,
            title: title,
            streamKey: streamKey,
            containerExtension: containerExtension,
            plot: plot,
            stillURL: stillURL.flatMap { URL(string: $0) },
            durationSeconds: durationSeconds,
            airDate: airDate
        )
    }
}

// MARK: - EPG

struct EPGProgramRecord: Codable, FetchableRecord, PersistableRecord {

    static let databaseTableName = "epgProgram"

    var id: String
    var epgChannelId: String
    var title: String
    var summary: String?
    var startDate: Date
    var endDate: Date

    init(_ program: EPGProgram) {
        self.id = program.id.value
        self.epgChannelId = program.epgChannelID
        self.title = program.title
        self.summary = program.summary
        self.startDate = program.startDate
        self.endDate = program.endDate
    }

    func toDomain() -> EPGProgram {
        EPGProgram(
            id: EPGProgram.ID(id),
            epgChannelID: epgChannelId,
            title: title,
            summary: summary,
            startDate: startDate,
            endDate: endDate
        )
    }
}
