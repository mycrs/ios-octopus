import Foundation

/// Her kullanıcıya açık, isteğe bağlı örnek kitaplığın içerik ve atıf bilgileri.
/// Filmler bütünüyle oynatılır; özgün kapanış jenerikleri kesilmez.
public struct SampleLibraryCredit: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let creator: String
    public let copyrightNotice: String
    public let licenseName: String
    public let licenseURL: URL
    public let creditsURL: URL
    public let videoURL: URL
    public let artworkURL: URL?
    public let durationSeconds: Int
    public let releaseYear: Int
}

public enum SampleLibraryCatalog {
    public static let playlistID = Playlist.ID("sample-library")
    public static let playlistName = "Örnek Kitaplık"
    public static let collectionTitle = "Örnek Açık Filmler / Sample Open Films"

    public static let credits: [SampleLibraryCredit] = [
        credit(
            id: "big-buck-bunny", title: "Big Buck Bunny",
            copyright: "© 2008 Blender Foundation / www.bigbuckbunny.org",
            team: "https://peach.blender.org/the-team/",
            video: "https://archive.org/download/BigBuckBunny_328/BigBuckBunny_512kb.mp4",
            artwork: "https://peach.blender.org/wp-content/uploads/bird1.jpg",
            duration: 596, year: 2008
        ),
        credit(
            id: "sintel", title: "Sintel",
            copyright: "© 2010 Blender Foundation / www.sintel.org",
            team: "https://durian.blender.org/about/",
            video: "https://archive.org/download/Sintel/sintel-2048-stereo_512kb.mp4",
            artwork: "https://durian.blender.org/wp-content/uploads/2010/06/02.b_comp_000296.jpg",
            duration: 888, year: 2010
        )
    ].compactMap { $0 }

    private static func credit(
        id: String, title: String, copyright: String, team: String,
        video: String, artwork: String?, duration: Int, year: Int
    ) -> SampleLibraryCredit? {
        guard let licenseURL = URL(string: "https://creativecommons.org/licenses/by/3.0/"),
              let creditsURL = URL(string: team), let videoURL = URL(string: video)
        else { return nil }
        return SampleLibraryCredit(
            id: id, title: title, creator: "Blender Foundation",
            copyrightNotice: copyright, licenseName: "Creative Commons Attribution 3.0",
            licenseURL: licenseURL, creditsURL: creditsURL, videoURL: videoURL,
            artworkURL: artwork.flatMap { URL(string: $0) },
            durationSeconds: duration, releaseYear: year
        )
    }
}
