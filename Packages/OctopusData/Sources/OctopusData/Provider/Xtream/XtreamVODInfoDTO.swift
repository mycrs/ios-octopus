import Foundation
import OctopusDomain

/// `get_vod_info` cevabı: film künyesi.
///
/// Liste ucu yalnızca ad, afiş ve puan döndürür; özet, oyuncular ve süre
/// ayrı bir istekle gelir. Detay ekranı açılınca çekilir.
struct XtreamVODInfoDTO: Decodable {

    let info: Info?
    let movieData: MovieData?

    enum CodingKeys: String, CodingKey {
        case info
        case movieData = "movie_data"
    }

    struct Info: Decodable {
        @Lenient var plot: String?
        @Lenient var cast: String?
        @Lenient var director: String?
        @Lenient var genre: String?
        @Lenient var releasedate: String?
        @Lenient var durationSecs: Int?
        @Lenient var rating: Double?
        @Lenient var movieImage: String?
        @Lenient var backdropPath: [String]?

        enum CodingKeys: String, CodingKey {
            case plot, cast, director, genre, rating, releasedate
            case durationSecs = "duration_secs"
            case movieImage = "movie_image"
            case backdropPath = "backdrop_path"
        }
    }

    struct MovieData: Decodable {
        @Lenient var name: String?
        @Lenient var containerExtension: String?
        @Lenient var added: Int?

        enum CodingKeys: String, CodingKey {
            case name, added
            case containerExtension = "container_extension"
        }
    }

    /// Var olan filmi zenginleştirir.
    ///
    /// Detay ucu bazı alanları boş döndürebiliyor; mevcut değerler
    /// korunur, yalnızca dolu gelenler yazılır. Aksi halde liste ucundan
    /// gelen sağlam veriler silinirdi.
    func enrich(_ movie: Movie) -> Movie {
        var result = movie

        if let plot = info?.plot, !plot.isEmpty { result.plot = plot }
        if let director = info?.director, !director.isEmpty { result.director = director }
        if let rating = info?.rating, rating > 0 { result.rating = rating }
        if let duration = info?.durationSecs, duration > 0 { result.durationSeconds = duration }

        let genres = XtreamList.split(info?.genre)
        if !genres.isEmpty { result.genres = genres }

        let cast = XtreamList.split(info?.cast)
        if !cast.isEmpty { result.cast = cast }

        if let releaseDate = XtreamDate.fromDayString(info?.releasedate) {
            result.releaseDate = releaseDate
        }
        if let backdrop = backdropPath.flatMap({ URL(string: $0) }) {
            result.backdropURL = backdrop
        }
        if let poster = info?.movieImage.flatMap({ URL(string: $0) }) {
            result.posterURL = poster
        }
        if let ext = movieData?.containerExtension, !ext.isEmpty {
            result.containerExtension = ext
        }
        if let added = XtreamDate.fromEpoch(movieData?.added) {
            result.addedAt = added
        }

        return result
    }

    /// `backdrop_path` dizi olarak gelir; ilki kullanılır.
    private var backdropPath: String? {
        info?.backdropPath?.first
    }
}
