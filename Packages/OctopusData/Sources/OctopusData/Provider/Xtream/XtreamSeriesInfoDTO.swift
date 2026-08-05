import Foundation
import OctopusDomain

/// `get_series_info` cevabı: sezon listesi ve bölüm ağacı.
///
/// ⚠️ `episodes` bir **sözlüktür**: anahtar sezon numarası, değer o sezonun
/// bölümleri. Bazı paneller sezonsuz dizilerde bunu düz dizi olarak
/// döndürür; ikisi de kabul edilir.
struct XtreamSeriesInfoDTO: Decodable {

    let seasons: [XtreamSeasonDTO]?
    let episodes: EpisodeTree?

    /// Panel biçim tutarsızlığını soğuran sarmalayıcı.
    enum EpisodeTree: Decodable {
        case bySeason([String: [XtreamEpisodeDTO]])
        case flat([XtreamEpisodeDTO])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let bySeason = try? container.decode([String: [XtreamEpisodeDTO]].self) {
                self = .bySeason(bySeason)
            } else if let flat = try? container.decode([XtreamEpisodeDTO].self) {
                self = .flat(flat)
            } else {
                self = .flat([])
            }
        }

        /// Sezon numarası → bölümler.
        var grouped: [Int: [XtreamEpisodeDTO]] {
            switch self {
            case .bySeason(let dictionary):
                var result: [Int: [XtreamEpisodeDTO]] = [:]
                for (key, value) in dictionary {
                    // Anahtar sezon numarasıdır; okunamıyorsa 1. sezon sayılır.
                    result[Int(key) ?? 1, default: []].append(contentsOf: value)
                }
                return result
            case .flat(let episodes):
                // Sezon bilgisi yoksa hepsi 1. sezon.
                return [1: episodes]
            }
        }
    }
}

struct XtreamSeasonDTO: Decodable {
    @Lenient var seasonNumber: Int?
    @Lenient var name: String?
    @Lenient var cover: String?
    @Lenient var episodeCount: Int?

    enum CodingKeys: String, CodingKey {
        case name, cover
        case seasonNumber = "season_number"
        case episodeCount = "episode_count"
    }
}

struct XtreamEpisodeDTO: Decodable {
    @Lenient var id: String?
    @Lenient var episodeNum: Int?
    @Lenient var title: String?
    @Lenient var containerExtension: String?
    @Lenient var season: Int?
    var info: Info?

    struct Info: Decodable {
        @Lenient var plot: String?
        @Lenient var durationSecs: Int?
        @Lenient var movieImage: String?
        @Lenient var releaseDate: String?

        enum CodingKeys: String, CodingKey {
            case plot
            case durationSecs = "duration_secs"
            case movieImage = "movie_image"
            case releaseDate = "releaseDate"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, season, info
        case episodeNum = "episode_num"
        case containerExtension = "container_extension"
    }

    func toDomain(seriesID: Series.ID, seasonNumber: Int) -> Episode? {
        // Akış anahtarı olmadan bölüm oynatılamaz.
        guard let rawID = id, !rawID.isEmpty else { return nil }
        let number = episodeNum ?? 0

        return Episode(
            id: EntityID.episode(seriesID: seriesID, rawID: rawID),
            seriesID: seriesID,
            seasonNumber: seasonNumber,
            number: number,
            // Başlıksız bölümler yaygın; "Bölüm 7" kullanıcıya boş metinden iyi.
            title: title ?? "Bölüm \(number)",
            streamKey: rawID,
            containerExtension: containerExtension ?? "mp4",
            plot: info?.plot,
            stillURL: info?.movieImage.flatMap { URL(string: $0) },
            durationSeconds: info?.durationSecs,
            airDate: XtreamDate.fromDayString(info?.releaseDate)
        )
    }
}

extension XtreamSeriesInfoDTO {

    /// Sezon ve bölüm listelerini üretir.
    ///
    /// Sezon listesi panelde eksik olabiliyor; o durumda bölümlerden
    /// türetilir — aksi halde dizi "sezonsuz" görünüp açılamazdı.
    func toDomain(seriesID: Series.ID) -> (seasons: [Season], episodes: [Episode]) {
        let grouped = episodes?.grouped ?? [:]

        var allEpisodes: [Episode] = []
        for (seasonNumber, dtos) in grouped {
            for dto in dtos {
                // Bölümün kendi sezon alanı varsa ona güvenilir.
                let resolvedSeason = dto.season ?? seasonNumber
                if let episode = dto.toDomain(seriesID: seriesID, seasonNumber: resolvedSeason) {
                    allEpisodes.append(episode)
                }
            }
        }
        allEpisodes.sort {
            ($0.seasonNumber, $0.number) < ($1.seasonNumber, $1.number)
        }

        let declaredSeasons = (seasons ?? []).compactMap { dto -> Season? in
            guard let number = dto.seasonNumber else { return nil }
            return Season(
                id: EntityID.season(seriesID: seriesID, number: number),
                seriesID: seriesID,
                number: number,
                name: dto.name,
                posterURL: dto.cover.flatMap { URL(string: $0) },
                episodeCount: dto.episodeCount ?? 0
            )
        }

        // Panel sezon listesi göndermediyse veya eksik gönderdiyse,
        // bölümlerde geçen sezon numaralarından tamamlanır.
        let seasonNumbersFromEpisodes = Set(allEpisodes.map(\.seasonNumber))
        let declaredNumbers = Set(declaredSeasons.map(\.number))
        let missing = seasonNumbersFromEpisodes.subtracting(declaredNumbers)

        let derivedSeasons = missing.map { number in
            Season(
                id: EntityID.season(seriesID: seriesID, number: number),
                seriesID: seriesID,
                number: number,
                name: nil,
                posterURL: nil,
                episodeCount: allEpisodes.filter { $0.seasonNumber == number }.count
            )
        }

        let combined = (declaredSeasons + derivedSeasons)
            // Bölümü olmayan sezon gösterilmez: kullanıcı boş listeye tıklar.
            .filter { seasonNumbersFromEpisodes.contains($0.number) }
            .sorted { $0.number < $1.number }

        return (combined, allEpisodes)
    }
}
