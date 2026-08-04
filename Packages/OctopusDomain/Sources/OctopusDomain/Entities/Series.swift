import Foundation

/// Dizi (üst kayıt). Sezon ve bölümler ayrı entity'lerdir —
/// 40 sezonluk bir diziyi tek nesnede taşımak listeleri kilitler.
public struct Series: Identifiable, Hashable, Codable, Sendable {

    public typealias ID = Identifier<Series>

    public let id: ID
    public let playlistID: Playlist.ID

    public var title: String
    public var posterURL: URL?
    public var backdropURL: URL?
    public var categoryID: MediaCategory.ID?

    public var plot: String?
    public var rating: Double?
    public var genres: [String]
    public var cast: [String]
    public var releaseDate: Date?
    public var lastModified: Date?

    public init(
        id: ID,
        playlistID: Playlist.ID,
        title: String,
        posterURL: URL? = nil,
        backdropURL: URL? = nil,
        categoryID: MediaCategory.ID? = nil,
        plot: String? = nil,
        rating: Double? = nil,
        genres: [String] = [],
        cast: [String] = [],
        releaseDate: Date? = nil,
        lastModified: Date? = nil
    ) {
        self.id = id
        self.playlistID = playlistID
        self.title = title
        self.posterURL = posterURL
        self.backdropURL = backdropURL
        self.categoryID = categoryID
        self.plot = plot
        self.rating = rating
        self.genres = genres
        self.cast = cast
        self.releaseDate = releaseDate
        self.lastModified = lastModified
    }
}

/// Sezon.
public struct Season: Identifiable, Hashable, Codable, Sendable {

    public typealias ID = Identifier<Season>

    public let id: ID
    public let seriesID: Series.ID
    public var number: Int
    public var name: String?
    public var posterURL: URL?
    public var episodeCount: Int

    public init(
        id: ID,
        seriesID: Series.ID,
        number: Int,
        name: String? = nil,
        posterURL: URL? = nil,
        episodeCount: Int = 0
    ) {
        self.id = id
        self.seriesID = seriesID
        self.number = number
        self.name = name
        self.posterURL = posterURL
        self.episodeCount = episodeCount
    }
}

/// Bölüm — oynatılabilir en küçük dizi birimi.
public struct Episode: Identifiable, Hashable, Codable, Sendable {

    public typealias ID = Identifier<Episode>

    public let id: ID
    public let seriesID: Series.ID
    public let seasonNumber: Int

    public var number: Int
    public var title: String
    public var streamKey: String
    public var containerExtension: String?

    public var plot: String?
    public var stillURL: URL?
    public var durationSeconds: Int?
    public var airDate: Date?

    public init(
        id: ID,
        seriesID: Series.ID,
        seasonNumber: Int,
        number: Int,
        title: String,
        streamKey: String,
        containerExtension: String? = nil,
        plot: String? = nil,
        stillURL: URL? = nil,
        durationSeconds: Int? = nil,
        airDate: Date? = nil
    ) {
        self.id = id
        self.seriesID = seriesID
        self.seasonNumber = seasonNumber
        self.number = number
        self.title = title
        self.streamKey = streamKey
        self.containerExtension = containerExtension
        self.plot = plot
        self.stillURL = stillURL
        self.durationSeconds = durationSeconds
        self.airDate = airDate
    }

    /// "S02B07" biçiminde kısa etiket.
    public var shortLabel: String {
        String(format: "S%02dB%02d", seasonNumber, number)
    }
}
