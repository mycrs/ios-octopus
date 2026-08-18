import XCTest
import Foundation
@testable import OctopusPlayback

@MainActor
final class PlaybackPreferencesTests: XCTestCase {

    func test_defaults_areSafeForFirstLaunch() {
        let (preferences, _, _) = makePreferences()

        XCTAssertEqual(preferences.videoFit, .fit)
        // Varsayılan **Kararlı**: takılan bir yayın, geç açılan yayından
        // daha kötü bir ilk izlenim bırakıyor.
        XCTAssertEqual(preferences.liveBuffer, .stable)
        XCTAssertTrue(preferences.autoReconnect)
        XCTAssertTrue(preferences.useFallbackEngine)
    }

    func test_allPlaybackSettingsPersist() {
        let (preferences, store, suite) = makePreferences()
        defer { store.removePersistentDomain(forName: suite) }

        preferences.videoFit = .fill
        preferences.liveBuffer = .stable
        preferences.autoReconnect = false
        preferences.useFallbackEngine = false

        let restored = PlaybackPreferences(store: store)

        XCTAssertEqual(restored.videoFit, .fill)
        XCTAssertEqual(restored.liveBuffer, .stable)
        XCTAssertFalse(restored.autoReconnect)
        XCTAssertFalse(restored.useFallbackEngine)
    }

    private func makePreferences() -> (PlaybackPreferences, UserDefaults, String) {
        let suite = "PlaybackPreferencesTests.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite) ?? .standard
        store.removePersistentDomain(forName: suite)
        return (PlaybackPreferences(store: store), store, suite)
    }
}
