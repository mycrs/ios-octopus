import XCTest

/// Gerçek Release akışı: DEBUG katalog bayrağı veya reviewer'a özel mod yok.
final class ReviewJourneyTests: XCTestCase {
    private var app: XCUIApplication!
    private var lastWindowObservation: [String: Any] = [:]

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        try IPadFullScreenAppsPreflight.configureIfNeeded(in: self)
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
        let homeFilm = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "home.movie.", "Big Buck Bunny"
        )).firstMatch
        XCTAssertTrue(homeFilm.waitForExistence(timeout: 20),
                      "Örnek kitaplığın gerçek filmi ana sayfada görünmeli")
        capture("03-home")
        movies.tap()
        let movieCards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "movie.card."))
        let movie = movieCards.firstMatch
        XCTAssertTrue(movie.waitForExistence(timeout: 20))
        let cardFrame = movie.frame
        let windowFrame = try XCTUnwrap(observedContentWindow(in: app)).frame
        XCTAssertGreaterThanOrEqual(cardFrame.minX, windowFrame.minX - 1,
                                    "Dolgulu afiş kartın erişilebilirlik alanını ekran dışına taşırmamalı")
        XCTAssertLessThanOrEqual(cardFrame.maxX, windowFrame.maxX + 1)
        let neighbour = movieCards.element(boundBy: 1)
        if neighbour.exists {
            XCTAssertFalse(cardFrame.intersects(neighbour.frame),
                           "Yan yana film kartlarının dokunma alanları çakışmamalı")
        }
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
        assertWindowOrientation(isLandscape: true)
        // Upright phone/tablet posture must not rotate the fullscreen player back.
        XCUIDevice.shared.orientation = .landscapeRight
        assertWindowOrientation(isLandscape: true)
        XCUIDevice.shared.orientation = .portrait
        assertWindowOrientation(isLandscape: true)
        assertFullscreenIgnoresPortraitPosture()
        // Element screenshots can crop incorrectly when device posture and
        // the locked scene disagree. Capture the physical screen after alignment.
        XCUIDevice.shared.orientation = .landscapeRight
        assertWindowOrientation(isLandscape: true)
        assertVideoFillsWindow()
        // A normal pause keeps the real controls visible while a slow screenshot
        // is captured; the ready video frame remains displayed by AVPlayerLayer.
        revealAndTapPlayerButton("player.playPause")
        let paused = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@ AND enabled == true", "Play"),
            object: app.buttons["player.playPause"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [paused], timeout: 10), .completed)
        capture("06-player", fullScreen: true)
        XCUIDevice.shared.orientation = .portrait
        assertFullscreenIgnoresPortraitPosture()
        closePlayer(nativeVideo: nativeVideo)
        assertWindowOrientation(isLandscape: false)
        XCTAssertTrue(play.waitForExistence(timeout: 10), "Kapatınca filmi açtığımız detay ekranı korunmalı")
        try verifyLiveFullscreenReturn()

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

    private func capture(_ name: String, fullScreen: Bool = false) {
        let screenshot = fullScreen ? XCUIScreen.main.screenshot() : app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertVideoFillsWindow() {
        let fillsWindow = XCTNSPredicateExpectation(predicate: NSPredicate { [app] _, _ in
            guard let app = app, let window = self.observedContentWindow(in: app),
                  window.frame.width > window.frame.height else { return false }
            // Observe both coordinate spaces in the same window snapshot. A
            // retained global AX identity can report its previous portrait frame.
            var pending = window.snapshot.children
            var native: (any XCUIElementSnapshot)?
            while let child = pending.popLast() {
                if child.identifier == "player.native-video" {
                    guard native == nil else { return false } // Ambiguous surfaces fail.
                    native = child
                }
                pending.append(contentsOf: child.children)
            }
            guard let native, native.value as? String == "ready" else { return false }
            let video = native.frame
            guard video.minX.isFinite, video.minY.isFinite,
                  video.width.isFinite, video.height.isFinite,
                  video.width > 0, video.height > 0 else { return false }
            return abs(video.minX - window.frame.minX) <= 1 && abs(video.minY - window.frame.minY) <= 1
                && abs(video.width - window.frame.width) <= 1 && abs(video.height - window.frame.height) <= 1
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [fillsWindow], timeout: 10), .completed,
                       "Video yüzeyi yatay pencerenin tamamını kaplamalı")
    }

    private func assertWindowOrientation(isLandscape: Bool) {
        let orientation = XCTNSPredicateExpectation(predicate: NSPredicate { [app] _, _ in
            guard let app = app, let frame = self.observedContentWindow(in: app)?.frame else { return false }
            return isLandscape ? frame.width > frame.height : frame.height > frame.width
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [orientation], timeout: 10), .completed,
                       isLandscape ? "Tam ekran oynatıcı yatay kalmalı" : "Kapatınca önceki dikey yön geri gelmeli")
    }

    private func assertFullscreenIgnoresPortraitPosture() {
        let began = ProcessInfo.processInfo.systemUptime
        var firstLandscape: TimeInterval?
        var consecutiveLandscapes = 0
        var sawNonLandscape = false
        var observations: [[String: Any]] = []
        let stable = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            let requested = ProcessInfo.processInfo.systemUptime - began
            let window = observedContentWindow(in: app)
            let elapsed = ProcessInfo.processInfo.systemUptime - began
            var observation: [String: Any] = [
                "index": observations.count, "requestedSeconds": requested,
                "observedSeconds": elapsed, "status": "unavailable"
            ]
            defer { observations.append(observation) }
            guard let frame = window?.frame else {
                // Unknown geometry is neither portrait nor evidence of landscape.
                firstLandscape = nil
                consecutiveLandscapes = 0
                return false
            }
            observation["frame"] = [frame.minX, frame.minY, frame.width, frame.height]
            guard frame.width > frame.height else {
                observation["status"] = "non_landscape"
                sawNonLandscape = true
                return true // Stop observing; the assertion below must fail.
            }
            observation["status"] = "landscape"
            if firstLandscape == nil { firstLandscape = elapsed }
            consecutiveLandscapes += 1
            return consecutiveLandscapes >= 3 && elapsed - (firstLandscape ?? elapsed) >= 2
        }, object: app)
        let result = XCTWaiter.wait(for: [stable], timeout: 10)
        if let data = try? JSONSerialization.data(withJSONObject: observations, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            let attachment = XCTAttachment(string: text)
            attachment.name = "fullscreen-posture-observations"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        if sawNonLandscape || result != .completed {
            capture("fullscreen-posture-failed", fullScreen: true)
        }
        XCTAssertFalse(sawNonLandscape,
                       "Cihaz dik tutulunca tam ekran oyuncu yataydan çıkmamalı")
        XCTAssertEqual(result, .completed,
                       "Tam ekranın en az 2 saniye yatay kaldığı üç yeni pencere gözlemiyle doğrulanmalı")
    }

    private func verifyLiveFullscreenReturn() throws {
        let live = app.buttons["Live TV"].firstMatch
        XCTAssertTrue(live.waitForExistence(timeout: 10))
        live.tap()
        let firstChannel = app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS %@", "live.channel", "Big Buck Bunny"
        )).firstMatch
        XCTAssertTrue(firstChannel.waitForExistence(timeout: 20))
        firstChannel.tap()
        let mini = app.descendants(matching: .any).matching(identifier: "live.miniPlayer").firstMatch
        XCTAssertTrue(mini.waitForExistence(timeout: 15))
        waitForNativeFrame()
        mini.tap()
        assertWindowOrientation(isLandscape: true)
        waitForNativeFrame()
        assertVideoFillsWindow()

        revealAndTapPlayerButton("player.channels.open")
        let currentRow = app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS %@", "player.channels.channel", "Big Buck Bunny"
        )).firstMatch
        XCTAssertTrue(currentRow.waitForExistence(timeout: 10))
        XCTAssertTrue(currentRow.isSelected, "Liste açık kanalı seçili göstermeli")
        let panelWindowFrame = try XCTUnwrap(observedContentWindow(in: app)).frame
        XCTAssertLessThan(currentRow.frame.maxX, panelWindowFrame.midX,
                          "Kanal listesi yatay videonun sol tarafında kalmalı")
        currentRow.tap()
        XCTAssertFalse(app.buttons["player.channels.close"].exists, "Mevcut kanala dokunmak paneli kapatmalı")
        waitForNativeFrame()

        revealAndTapPlayerButton("player.channels.open")
        let search = app.textFields["player.channels.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("Sintel\n")
        let nextChannel = app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS %@", "player.channels.channel", "Sintel"
        )).firstMatch
        XCTAssertTrue(nextChannel.waitForExistence(timeout: 10))
        XCTAssertTrue(nextChannel.isHittable)
        nextChannel.tap()
        waitForNativeFrame()
        revealAndTapPlayerButton("player.close")
        assertWindowOrientation(isLandscape: false)
        waitForLivePreview()
        waitForLivePreview(channel: "Sintel")
        waitForNativePreview()
        try tapLivePreview()
        assertWindowOrientation(isLandscape: true)
        waitForNativeFrame()
        // Holding a real control beyond the 3.5s inactivity timeout must keep
        // it alive until release, then return to the same live preview.
        revealAndTapPlayerButton("player.close", pressDuration: 4)
        assertWindowOrientation(isLandscape: false)
        waitForLivePreview()
        waitForLivePreview(channel: "Sintel")
        waitForNativePreview()
        // A containing SwiftUI AX element may have no computed activation point.
        // Prove the returned preview accepts a real touch and owns the video again.
        try tapLivePreview()
        assertWindowOrientation(isLandscape: true)
        waitForNativeFrame()
        assertVideoFillsWindow()
        revealAndTapPlayerButton("player.close")
        assertWindowOrientation(isLandscape: false)
        waitForLivePreview()
        waitForLivePreview(channel: "Sintel")
        waitForNativePreview()
    }

    private func waitForNativeFrame() {
        let surface = app.descendants(matching: .any).matching(identifier: "player.native-video").firstMatch
        let rendered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND value == %@", "ready"), object: surface)
        XCTAssertEqual(XCTWaiter.wait(for: [rendered], timeout: 45), .completed,
                       "Gerçek AVPlayerLayer ilk kareyi göstermeli")
    }

    private func waitForLivePreview(channel: String? = nil) {
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            guard let window = observedContentWindow(in: app),
                  let mini = observedLivePreview(in: window) else { return false }
            return channel.map { mini.label.contains($0) } ?? true
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 10), .completed,
                       "Tam ekranda seçilen kanal aynı dikey mini oynatıcıya devredilmeli")
    }

    private func tapLivePreview() throws {
        let window = try XCTUnwrap(observedContentWindow(in: app))
        let mini = try XCTUnwrap(observedLivePreview(in: window))
        XCTAssertTrue(tapObservedPlayerButton(mini.frame, window: window.element,
                                             windowFrame: window.frame))
    }

    private func waitForNativePreview() {
        let rendered = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            guard let window = observedContentWindow(in: app),
                  let mini = observedLivePreview(in: window),
                  let surface = uniqueDescendant("player.native-video", in: mini),
                  surface.value as? String == "ready" else { return false }
            let preview = mini.frame
            let video = surface.frame
            guard preview.minX.isFinite, preview.minY.isFinite,
                  preview.width.isFinite, preview.height.isFinite,
                  video.minX.isFinite, video.minY.isFinite,
                  video.width.isFinite, video.height.isFinite,
                  preview.width > 0, preview.height > 0, video.width > 0, video.height > 0,
                  window.frame.contains(preview) else { return false }
            return abs(video.minX - preview.minX) <= 1 && abs(video.minY - preview.minY) <= 1
                && abs(video.width - preview.width) <= 1 && abs(video.height - preview.height) <= 1
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [rendered], timeout: 45), .completed,
                       "Dönen mini oynatıcı kendi hazır native video yüzeyini göstermeli")
    }

    private func revealAndTapPlayerButton(_ identifier: String, pressDuration: TimeInterval = 0) {
        for _ in 0..<3 {
            guard let window = waitForContentWindow() else { continue }
            if playerActionCompleted(identifier, window: window) { return }
            if performPlayerControl(identifier, window: window, pressDuration: pressDuration) {
                if identifier == "player.playPause" {
                    // Tap delivery is not action completion. The caller's mandatory
                    // 10s Play + enabled predicate proves pause without toggling it again.
                    return
                }
                let completed = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
                    self.playerActionCompleted(identifier)
                }, object: app)
                if XCTWaiter.wait(for: [completed], timeout: 2) == .completed { return }
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: lastWindowObservation, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            let attachment = XCTAttachment(string: text)
            attachment.name = "player-control-window-observation"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        capture("player-control-failed", fullScreen: true)
        XCTFail("Oynatıcı denetiminin işlemi tamamlanmalı: \(identifier)")
    }

    private func playerActionCompleted(_ identifier: String, window: ContentWindow? = nil) -> Bool {
        switch identifier {
        case "player.playPause":
            // Controls can disappear between independent AX queries. Read the
            // enabled control and its label from the same observed window tree.
            guard let window = window ?? observedContentWindow(in: app),
                  observedPlayerButtonFrame(identifier, window: window) != nil,
                  let button = uniqueDescendant(identifier, in: window.snapshot) else { return false }
            return button.label == "Play"
        case "player.channels.open":
            guard let window = window ?? observedContentWindow(in: app) else { return false }
            return observedPlayerButtonFrame("player.channels.close", window: window) != nil
                && uniqueDescendant("player.channels.close", in: window.snapshot) != nil
        case "player.close":
            guard let window = window ?? observedContentWindow(in: app) else { return false }
            return observedLivePreview(in: window) != nil
        default:
            return false
        }
    }

    private func closePlayer(nativeVideo: XCUIElement) {
        // Denetimler oynarken 3.5 saniyede gizlenir. AX/screenshot işlemleri
        // bu süreyi aşabilir; arka plandaki sekmeler yine exists döndürür.
        for _ in 0..<3 {
            if !nativeVideo.exists { return }
            guard let window = observedContentWindow(in: app) else { continue }
            let observed = refreshPlayerControls("player.close", window: window)
            if let frame = playerButtonFrame("player.close", window: window, observed: observed) {
                _ = tapObservedPlayerButton(frame, window: window.element, windowFrame: window.frame)
            }
            let dismissed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"), object: nativeVideo
            )
            if XCTWaiter.wait(for: [dismissed], timeout: 3) == .completed { return }
        }
        capture("player-close-failed")
        XCTFail("Sekme değiştirilmeden önce tam ekran oynatıcı kapanmalı")
    }

    /// Read the current window's snapshot, then reveal using its coordinate space.
    /// A retained global query can miss controls that the physical video shows.
    private func refreshPlayerControls(
        _ identifier: String, window: ContentWindow
    ) -> CGRect? {
        if let frame = observedPlayerButtonFrame(identifier, window: window) { return frame }
        window.element.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.24)).tap()
        return nil
    }

    private func performPlayerControl(
        _ identifier: String, window: ContentWindow, pressDuration: TimeInterval
    ) -> Bool {
        let observed = refreshPlayerControls(identifier, window: window)
        guard let frame = playerButtonFrame(identifier, window: window, observed: observed) else { return false }
        guard pressDuration > 0 || identifier == "player.playPause" else {
            return tapObservedPlayerButton(frame, window: window.element, windowFrame: window.frame)
        }
        // Observe the real enabled control before hiding it. Once a fresh window
        // proves it is hidden, reveal and touch without another explicit AX read.
        // A pause tap also needs a fresh reveal: the old control can disappear
        // while the input driver resolves the observed window and button frame.
        // The observed frame is only a touch target; outcome/native checks remain.
        window.element.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.24)).tap()
        guard let hidden = waitForHiddenPlayerWindow(identifier, matching: window),
              hidden.frame.contains(frame) else { return false }
        hidden.element.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.24)).tap()
        return tapObservedPlayerButton(frame, window: hidden.element, windowFrame: hidden.frame,
                                       pressDuration: pressDuration)
    }

    private func waitForHiddenPlayerWindow(
        _ identifier: String, matching previous: ContentWindow
    ) -> ContentWindow? {
        var hidden: ContentWindow?
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            guard let observed = observedHiddenPlayerWindow(identifier, matching: previous) else {
                return false
            }
            hidden = observed
            return true
        }, object: app)
        // The opacity transition must finish before hidden controls are observed.
        guard XCTWaiter.wait(for: [ready], timeout: 2) == .completed else { return nil }
        return hidden
    }

    private func observedHiddenPlayerWindow(
        _ identifier: String, matching previous: ContentWindow
    ) -> ContentWindow? {
        guard let window = observedContentWindow(in: app), window.frame.width > window.frame.height,
              abs(window.frame.minX - previous.frame.minX) <= 1,
              abs(window.frame.minY - previous.frame.minY) <= 1,
              abs(window.frame.width - previous.frame.width) <= 1,
              abs(window.frame.height - previous.frame.height) <= 1,
              !containsDescendant(identifier, in: window.snapshot),
              let native = uniqueDescendant("player.native-video", in: window.snapshot),
              native.value as? String == "ready" else { return nil }
        // A missing/empty AX tree cannot prove that controls were hidden.
        let video = native.frame
        guard video.minX.isFinite, video.minY.isFinite, video.width.isFinite, video.height.isFinite,
              video.width > 0, video.height > 0,
              abs(video.minX - window.frame.minX) <= 1, abs(video.minY - window.frame.minY) <= 1,
              abs(video.width - window.frame.width) <= 1, abs(video.height - window.frame.height) <= 1 else { return nil }
        return window
    }

    /// Carry the same snapshot geometry into the real tap. Only the unchanged
    /// action/native/orientation assertions establish completion.
    private func playerButtonFrame(
        _ identifier: String, window: ContentWindow, observed: CGRect?
    ) -> CGRect? {
        if let observed { return observed }
        if let frame = refreshedPlayerButtonFrame(identifier, window: window) { return frame }
        var frame: CGRect?
        let visible = XCTNSPredicateExpectation(
            predicate: NSPredicate { [self] _, _ in
                frame = refreshedPlayerButtonFrame(identifier, window: window)
                return frame != nil
            }, object: window.element
        )
        return XCTWaiter.wait(for: [visible], timeout: 2) == .completed ? frame : nil
    }

    private func refreshedPlayerButtonFrame(_ identifier: String, window: ContentWindow) -> CGRect? {
        guard let snapshot = try? window.element.snapshot() else { return nil }
        let frame = snapshot.frame
        guard abs(frame.minX - window.frame.minX) <= 1, abs(frame.minY - window.frame.minY) <= 1,
              abs(frame.width - window.frame.width) <= 1, abs(frame.height - window.frame.height) <= 1 else { return nil }
        return observedPlayerButtonFrame(identifier, window: (window.element, frame, snapshot))
    }

    private func observedPlayerButtonFrame(_ identifier: String, window: ContentWindow) -> CGRect? {
        var pending = window.snapshot.children
        var button: (any XCUIElementSnapshot)?
        while let child = pending.popLast() {
            if child.elementType == .button, child.identifier == identifier {
                guard button == nil else { return nil }
                button = child
            }
            pending.append(contentsOf: child.children)
        }
        guard let button, button.isEnabled else { return nil }
        let frame = button.frame
        guard frame.minX.isFinite, frame.minY.isFinite, frame.width.isFinite, frame.height.isFinite,
              frame.width > 0, frame.height > 0, window.frame.contains(frame) else { return nil }
        return frame
    }

    /// Tap the observed in-window center without re-resolving a transient button.
    private func tapObservedPlayerButton(
        _ frame: CGRect, window: XCUIElement, windowFrame: CGRect,
        pressDuration: TimeInterval = 0
    ) -> Bool {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        guard frame.minX.isFinite, frame.minY.isFinite, frame.width.isFinite, frame.height.isFinite,
              frame.width > 0, frame.height > 0, windowFrame.contains(center) else { return false }
        let target = window.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: center.x - windowFrame.minX, dy: center.y - windowFrame.minY))
        if pressDuration > 0 {
            target.press(forDuration: pressDuration)
        } else {
            target.tap()
        }
        return true
    }

    private typealias ContentWindow = (element: XCUIElement, frame: CGRect, snapshot: any XCUIElementSnapshot)

    private func waitForContentWindow() -> ContentWindow? {
        if let window = observedContentWindow(in: app) { return window }
        var window: ContentWindow?
        let available = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            window = observedContentWindow(in: app)
            return window != nil
        }, object: app)
        return XCTWaiter.wait(for: [available], timeout: 2) == .completed ? window : nil
    }

    /// Dismissal retires AX identities. Resolve the receiver and its native child
    /// in one current, independent window snapshot; ambiguous matches fail.
    private func observedLivePreview(in window: ContentWindow) -> (any XCUIElementSnapshot)? {
        guard window.frame.height > window.frame.width,
              let mini = uniqueDescendant("live.miniPlayer", in: window.snapshot) else { return nil }
        let frame = mini.frame
        guard frame.minX.isFinite, frame.minY.isFinite, frame.width.isFinite, frame.height.isFinite,
              frame.width > 0, frame.height > 0, window.frame.contains(frame) else { return nil }
        return mini
    }

    private func uniqueDescendant(
        _ identifier: String, in snapshot: any XCUIElementSnapshot
    ) -> (any XCUIElementSnapshot)? {
        var pending = snapshot.children
        var match: (any XCUIElementSnapshot)?
        while let child = pending.popLast() {
            if child.identifier == identifier {
                guard match == nil else { return nil }
                match = child
            }
            pending.append(contentsOf: child.children)
        }
        return match
    }

    private func containsDescendant(_ identifier: String, in snapshot: any XCUIElementSnapshot) -> Bool {
        var pending = snapshot.children
        while let child = pending.popLast() {
            if child.identifier == identifier { return true }
            pending.append(contentsOf: child.children)
        }
        return false
    }

    /// Ignore zero-size auxiliary windows without selecting by expected orientation
    /// or by video bounds: geometry assertions still examine the independent window.
    private func observedContentWindow(in application: XCUIApplication) -> ContentWindow? {
        // Read geometry from one current tree, without resolving a window again
        // after an intervening rotation has retired its accessibility identity.
        lastWindowObservation = ["reason": "snapshot_unavailable"]
        guard let root = try? application.snapshot() else { return nil }
        let windows = root.children.filter { $0.elementType == .window }
        lastWindowObservation = ["reason": "no_positive_window", "windowCount": windows.count]
        let candidates = windows.enumerated().compactMap { index, snapshot ->
            (index: Int, frame: CGRect, snapshot: any XCUIElementSnapshot)? in
            let frame = snapshot.frame
            guard frame.minX.isFinite, frame.minY.isFinite, frame.width.isFinite, frame.height.isFinite,
                  frame.width > 0, frame.height > 0,
                  (frame.width * frame.height).isFinite else { return nil }
            return (index, frame, snapshot)
        }
        lastWindowObservation["validFrames"] = candidates.map { candidate -> [String: Any] in
            ["index": candidate.index,
             "frame": [candidate.frame.minX, candidate.frame.minY, candidate.frame.width, candidate.frame.height]]
        }
        guard let largest = candidates.max(by: {
            $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height
        }) else { return nil }
        let tied = candidates.filter {
            $0.frame.width * $0.frame.height == largest.frame.width * largest.frame.height
        }
        lastWindowObservation["largestCount"] = tied.count
        var selected = largest
        if tied.count > 1 {
            // Multiple windows can share the full display size. Identify the
            // single playback owner by identity, never by its video geometry,
            // ready state, or the orientation the assertion expects to see.
            lastWindowObservation["reason"] = "ambiguous_largest_windows"
            let owners = tied.filter { containsDescendant("player.native-video", in: $0.snapshot) }
            lastWindowObservation["playbackOwnerCount"] = owners.count
            guard owners.count == 1, let owner = owners.first,
                  uniqueDescendant("player.native-video", in: owner.snapshot) != nil else { return nil }
            selected = owner
            lastWindowObservation["reason"] = "unique_playback_owner"
        } else {
            lastWindowObservation["reason"] = "unique_largest_window"
        }
        lastWindowObservation["selectedIndex"] = selected.index
        // Construct only a lazy, matching child query for later input delivery.
        let element = application.children(matching: .window).element(boundBy: selected.index)
        return (element, selected.frame, selected.snapshot)
    }

    private func scrollTo(_ element: XCUIElement) {
        for _ in 0..<8 {
            if element.isHittable { return }
            app.swipeUp()
        }
    }
}
