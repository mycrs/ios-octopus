import Foundation
import OctopusDomain

/// Sağlayıcıdan gelen ham kimlikleri **global benzersiz** kimliklere çevirir.
///
/// ## Neden gerekli?
/// Xtream `stream_id` yalnızca kendi hesabı içinde benzersizdir. Kullanıcı iki
/// ayrı hesap eklediğinde ikisinde de "1234" numaralı kanal bulunabilir.
/// Ham kimlik doğrudan kullanılsaydı:
/// - bir kaynakta favoriye eklenen kanal, diğerinde de favori görünürdü
/// - izleme ilerlemesi yanlış içeriğe uygulanırdı
/// - kaynak silinince yanlış satırlar silinirdi
///
/// Bu yüzden kimlik `<playlistId>#<tür>#<hamId>` biçiminde kurulur.
/// Ham değer kaybolmaz; `streamKey` kolonunda saklanır ve akış URL'si
/// kurulurken oradan okunur.
enum EntityID {

    /// Ham değerlerde geçmesi beklenmeyen ayraç.
    private static let separator = "#"

    static func channel(playlistID: Playlist.ID, rawID: String) -> Channel.ID {
        Channel.ID(compose(playlistID, "live", rawID))
    }

    static func movie(playlistID: Playlist.ID, rawID: String) -> Movie.ID {
        Movie.ID(compose(playlistID, "vod", rawID))
    }

    static func series(playlistID: Playlist.ID, rawID: String) -> Series.ID {
        Series.ID(compose(playlistID, "series", rawID))
    }

    static func season(seriesID: Series.ID, number: Int) -> Season.ID {
        Season.ID("\(seriesID.value)\(separator)s\(number)")
    }

    static func episode(seriesID: Series.ID, rawID: String) -> Episode.ID {
        Episode.ID("\(seriesID.value)\(separator)e\(separator)\(sanitize(rawID))")
    }

    /// Kategori kimlikleri **tür içinde** benzersizdir: Xtream'de canlı ve film
    /// kategori listeleri ayrıdır ve id'leri çakışabilir.
    static func category(
        playlistID: Playlist.ID,
        kind: MediaCategory.Kind,
        rawID: String
    ) -> MediaCategory.ID {
        MediaCategory.ID(compose(playlistID, kind.rawValue, rawID))
    }

    /// EPG programları kaynağa değil XMLTV kanal kimliğine bağlıdır.
    static func epgProgram(epgChannelID: String, startDate: Date) -> EPGProgram.ID {
        EPGProgram.ID("\(sanitize(epgChannelID))\(separator)\(Int(startDate.timeIntervalSince1970))")
    }

    // MARK: - Yardımcılar

    private static func compose(
        _ playlistID: Playlist.ID,
        _ kind: String,
        _ rawID: String
    ) -> String {
        "\(playlistID.value)\(separator)\(kind)\(separator)\(sanitize(rawID))"
    }

    /// Ayraç ham veride geçerse kimlik bozulur — kaçırılır.
    private static func sanitize(_ raw: String) -> String {
        raw.replacingOccurrences(of: separator, with: "_")
    }
}
