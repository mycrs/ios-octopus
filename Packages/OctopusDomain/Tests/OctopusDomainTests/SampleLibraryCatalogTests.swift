import XCTest
@testable import OctopusDomain

final class SampleLibraryCatalogTests: XCTestCase {
    func test_everySampleFilmHasCompleteAttributionAndAFullLengthPublicMP4() {
        let films = SampleLibraryCatalog.credits
        XCTAssertEqual(films.count, 2)
        XCTAssertEqual(Set(films.map(\.id)).count, films.count)
        for film in films {
            XCTAssertFalse(film.creator.isEmpty)
            XCTAssertTrue(film.copyrightNotice.contains("Blender Foundation"))
            XCTAssertEqual(film.licenseURL.absoluteString, "https://creativecommons.org/licenses/by/3.0/")
            XCTAssertEqual(film.videoURL.scheme, "https")
            XCTAssertEqual(film.videoURL.pathExtension, "mp4")
            XCTAssertGreaterThan(film.durationSeconds, 500)
            XCTAssertEqual(film.creditsURL.scheme, "https")
        }
    }
}
