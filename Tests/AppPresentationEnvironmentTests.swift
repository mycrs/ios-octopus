import XCTest
import SwiftUI
import UIKit
import OctopusDesignSystem
import OctopusNavigation
import OctopusPlayback
@testable import Octopus

@MainActor
final class AppPresentationEnvironmentTests: XCTestCase {
    func test_separateHostReceivesSharedObjectsAndExistingPreferences() async throws {
        let fixture = try PresentationFixture()
        fixture.theme.select(.purple)
        fixture.language.select(.english)
        fixture.router.selectedTab = .live
        fixture.playback.liveBuffer = .fast
        fixture.playback.autoReconnect = false

        let rendered = expectation(description: "Separate presentation resolves its environment")
        var observed: PresentationSnapshot?
        let window = fixture.host { snapshot in
            guard observed == nil else { return }
            observed = snapshot
            rendered.fulfill()
        }
        defer { fixture.close(window) }
        await fulfillment(of: [rendered], timeout: 3)

        let snapshot = try XCTUnwrap(observed)
        XCTAssertEqual(snapshot.themeIdentity, ObjectIdentifier(fixture.theme))
        XCTAssertEqual(snapshot.languageIdentity, ObjectIdentifier(fixture.language))
        XCTAssertEqual(snapshot.routerIdentity, ObjectIdentifier(fixture.router))
        XCTAssertEqual(snapshot.playbackIdentity, ObjectIdentifier(fixture.playback))
        XCTAssertEqual(snapshot.brandColor, fixture.theme.accent)
        XCTAssertEqual(snapshot.localeIdentifier, fixture.language.locale.identifier)
        XCTAssertEqual(snapshot.selectedTab, .live)
        XCTAssertEqual(snapshot.liveBuffer, .fast)
        XCTAssertFalse(snapshot.autoReconnect)
    }

    func test_openPresentationTracksSharedThemeLanguageNavigationAndPlaybackChanges() async throws {
        let fixture = try PresentationFixture()
        fixture.playback.liveBuffer = .fast
        let initial = expectation(description: "Initial hosted projection")
        let updated = expectation(description: "Shared changes reach the open presentation")
        var initialSnapshot: PresentationSnapshot?
        var updatedSnapshot: PresentationSnapshot?
        let window = fixture.host { snapshot in
            if initialSnapshot == nil {
                initialSnapshot = snapshot
                initial.fulfill()
            }
            if snapshot.brandColor == Theme.BrandColor.green.color,
               snapshot.localeIdentifier == "en", snapshot.selectedTab == .movies,
               snapshot.liveBuffer == .stable, !snapshot.autoReconnect,
               updatedSnapshot == nil {
                updatedSnapshot = snapshot
                updated.fulfill()
            }
        }
        defer { fixture.close(window) }
        await fulfillment(of: [initial], timeout: 3)
        XCTAssertEqual(try XCTUnwrap(initialSnapshot).localeIdentifier, "tr")

        fixture.theme.select(.green)
        fixture.language.select(.english)
        fixture.router.selectedTab = .movies
        fixture.playback.liveBuffer = .stable
        fixture.playback.autoReconnect = false
        await fulfillment(of: [updated], timeout: 3)

        let snapshot = try XCTUnwrap(updatedSnapshot)
        XCTAssertEqual(snapshot.themeIdentity, ObjectIdentifier(fixture.theme))
        XCTAssertEqual(snapshot.languageIdentity, ObjectIdentifier(fixture.language))
        XCTAssertEqual(snapshot.routerIdentity, ObjectIdentifier(fixture.router))
        XCTAssertEqual(snapshot.playbackIdentity, ObjectIdentifier(fixture.playback))
        XCTAssertEqual(snapshot.brandColor, fixture.theme.accent)
        XCTAssertEqual(snapshot.localeIdentifier, fixture.language.locale.identifier)
        XCTAssertEqual(fixture.router.selectedTab, .movies)
        XCTAssertEqual(fixture.playback.liveBuffer, .stable)
        XCTAssertFalse(fixture.playback.autoReconnect)
    }
}

@MainActor
private struct PresentationFixture {
    let suiteName: String
    let store: UserDefaults
    let theme: ThemeController
    let language: LanguageController
    let router: AppRouter
    let playback: PlaybackPreferences

    init() throws {
        let name = "AppPresentationEnvironmentTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        suiteName = name
        store = defaults
        theme = ThemeController(store: defaults)
        language = LanguageController(store: defaults, preferredLanguages: { ["tr"] })
        router = AppRouter(store: defaults)
        playback = PlaybackPreferences(store: defaults)
    }

    func host(onObservation: @escaping (PresentationSnapshot) -> Void) -> UIWindow {
        let content = PresentationProbe(onObservation: onObservation)
            .modifier(AppPresentationEnvironment(
                theme: theme, language: language, router: router, playback: playback
            ))
        let controller = UIHostingController(rootView: content)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
        controller.view.layoutIfNeeded()
        return window
    }

    func close(_ window: UIWindow) {
        window.isHidden = true
        window.rootViewController = nil
        store.removePersistentDomain(forName: suiteName)
    }
}

private struct PresentationSnapshot: Equatable {
    let themeIdentity: ObjectIdentifier
    let languageIdentity: ObjectIdentifier
    let routerIdentity: ObjectIdentifier
    let playbackIdentity: ObjectIdentifier
    let brandColor: Color
    let localeIdentifier: String
    let selectedTab: AppTab
    let liveBuffer: PlaybackPreferences.LiveBuffer
    let autoReconnect: Bool
}

@MainActor
private struct PresentationProbe: View {
    @EnvironmentObject private var theme: ThemeController
    @EnvironmentObject private var language: LanguageController
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var playback: PlaybackPreferences
    @Environment(\.brandColor) private var brandColor
    @Environment(\.locale) private var locale
    let onObservation: (PresentationSnapshot) -> Void

    private var snapshot: PresentationSnapshot {
        PresentationSnapshot(
            themeIdentity: ObjectIdentifier(theme), languageIdentity: ObjectIdentifier(language),
            routerIdentity: ObjectIdentifier(router), playbackIdentity: ObjectIdentifier(playback),
            brandColor: brandColor, localeIdentifier: locale.identifier,
            selectedTab: router.selectedTab, liveBuffer: playback.liveBuffer,
            autoReconnect: playback.autoReconnect
        )
    }

    var body: some View {
        // These are the same deferred environment reads used by busy forms and Settings.
        Text(theme.resellerName ?? "Presentation probe")
            .onAppear { onObservation(snapshot) }
            .onChange(of: snapshot) { onObservation($0) }
    }
}
