import XCTest

/// Gerçek Release akışı: DEBUG katalog bayrağı veya reviewer'a özel mod yok.
final class ReviewJourneyTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-language.selection", "english"]
        app.launch()
    }

    func test_publicSampleLibraryAndViewingControls() throws {
        let entry = app.buttons["sample-library.open"].firstMatch
        if entry.waitForExistence(timeout: 12) {
            capture("01-welcome")
            entry.tap()
            let install = app.buttons["sample-library.install"]
            XCTAssertTrue(install.waitForExistence(timeout: 10))
            capture("02-sample-credits")
            install.tap()
        }

        let movies = app.buttons["Movies"].firstMatch
        XCTAssertTrue(movies.waitForExistence(timeout: 45))
        capture("03-home")
        movies.tap()
        let movie = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "movie.card.")).firstMatch
        XCTAssertTrue(movie.waitForExistence(timeout: 20))
        capture("04-movies")
        movie.tap()
        let play = app.buttons["movie.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 20))
        capture("05-movie-detail")
        play.tap()
        let close = app.buttons["player.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 30))
        let nativeVideo = app.descendants(matching: .any).matching(identifier: "player.native-video").firstMatch
        let rendered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "ready"), object: nativeVideo)
        XCTAssertEqual(XCTWaiter.wait(for: [rendered], timeout: 45), .completed,
                       "Oynatma durumu tek başına kare kanıtı değildir; gerçek AVPlayerLayer hazır olmalı")
        capture("06-player")
        if !close.isHittable { nativeVideo.tap() }
        close.tap()

        let series = app.buttons["Series"].firstMatch
        XCTAssertTrue(series.waitForExistence(timeout: 10))
        series.tap()
        let collection = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "series.card.")).firstMatch
        XCTAssertTrue(collection.waitForExistence(timeout: 20))
        capture("07-series")
        collection.tap()
        let episode = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "episode.card.")).firstMatch
        scrollTo(episode)
        XCTAssertTrue(episode.isHittable)
        capture("08-episodes")

        movies.tap()
        // Aynı sekmenin yığınına dönülür: film detayından köke geri dön.
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if app.buttons["movie.play"].exists, back.exists { back.tap() }
        let settings = app.buttons["navigation.settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        capture("09-settings")
        let sourceCheck = app.buttons["source-health.open"].firstMatch
        scrollTo(sourceCheck)
        XCTAssertTrue(sourceCheck.isHittable)
        sourceCheck.tap()
        XCTAssertTrue(app.staticTexts["source-health.catalog"].firstMatch.waitForExistence(timeout: 15))
        capture("10-source-check")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func scrollTo(_ element: XCUIElement) {
        for _ in 0..<8 {
            if element.isHittable { return }
            app.swipeUp()
        }
    }
}
