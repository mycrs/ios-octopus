import Foundation

/// VOD film.
public struct Movie: Identifiable, Hashable, Codable, Sendable {

    public typealias ID = Identifier<Movie>

    public let id: ID
    public let playlistID: Playlist.ID

    public var title: String
    public var streamKey: String

    /// Konteyner uzantısı (`mp4`, `mkv`, `avi`). Xtream akış URL'sini kurarken gerekir.
    public var containerExtension: String?

    public var posterURL: URL?
    public var backdropURL: URL?
    public var categoryID: MediaCategory.ID?

    public var plot: String?
    public var releaseDate: Date?
    public var durationSeconds: Int?
    public var rating: Double?
    public var genres: [String]
    public var cast: [String]
    public var director: String?

    public var isAdult: Bool
    public var addedAt: Date?

    public init(
        id: ID,
        playlistID: Playlist.ID,
        title: String,
        streamKey: String,
        containerExtension: String? = nil,
        posterURL: URL? = nil,
        backdropURL: URL? = nil,
        categoryID: MediaCategory.ID? = nil,
        plot: String? = nil,
        releaseDate: Date? = nil,
        durationSeconds: Int? = nil,
        rating: Double? = nil,
        genres: [String] = [],
        cast: [String] = [],
        director: String? = nil,
        isAdult: Bool = false,
        addedAt: Date? = nil
    ) {
        self.id = id
        self.playlistID = playlistID
        self.title = title
        self.streamKey = streamKey
        self.containerExtension = containerExtension
        self.posterURL = posterURL
        self.backdropURL = backdropURL
        self.categoryID = categoryID
        self.plot = plot
        self.releaseDate = releaseDate
        self.durationSeconds = durationSeconds
        self.rating = rating
        self.genres = genres
        self.cast = cast
        self.director = director
        self.isAdult = isAdult
        self.addedAt = addedAt
    }
}
