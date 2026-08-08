import Foundation
import UIKit
import XCTest
import OctopusDomain
@testable import OctopusPlayback

extension XCTestCase {

    /// Koşul sağlanana kadar kısa aralıklarla yoklar.
    ///
    /// ⚠️ Sabit `sleep` **kullanılmaz**: yerelde geçen test yüklü bir CI
    /// koşucusunda rastgele kırmızıya döner. Süreyi değil koşulu bekle
    /// (bkz. BRAIN.md § 11.1).
    /// - Note: `@escaping` zorunlu — `@MainActor` işaretli bir fonksiyon
    ///   aktöre atlarken parametrelerini kaçırmış sayılır:
    ///   "escaping local function captures non-escaping value".
    @MainActor
    func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)   // 20 ms
        }
        return condition()
    }
}

/// Olayları **elle** yayınlanabilen motor.
///
/// Gerçek motorla test etmek ağa ve zamanlamaya bağımlı olurdu;
/// koordinatörün asıl işi (yedeğe düşme, ilerleme kaydı, geçmiş)
/// motordan bağımsızdır ve burada deterministik olarak doğrulanır.
@MainActor
final class TestEngine: PlaybackEngine {

    let identifier: String
    let events: AsyncStream<PlaybackEvent>

    private(set) var currentState: PlaybackState = .idle
    private(set) var audioTracks: [MediaTrack] = []
    private(set) var subtitleTracks: [MediaTrack] = []
    var selectedAudioTrack: MediaTrack?
    var selectedSubtitleTrack: MediaTrack?
    let supportsPictureInPicture = false

    // Kayıt: koordinatörün motoru doğru güttüğünü doğrulamak için.
    private(set) var loadedItems: [PlaybackItem] = []
    private(set) var playCount = 0
    private(set) var pauseCount = 0
    private(set) var didTeardown = false
    private(set) var seekedTo: [TimeInterval] = []
    private(set) var selectedTracks: [MediaTrack] = []

    private let continuation: AsyncStream<PlaybackEvent>.Continuation

    init(identifier: String) {
        self.identifier = identifier
        var captured: AsyncStream<PlaybackEvent>.Continuation!
        self.events = AsyncStream { captured = $0 }
        self.continuation = captured
    }

    func emit(_ event: PlaybackEvent) {
        if case .stateChanged(let state) = event { currentState = state }
        continuation.yield(event)
    }

    func load(_ item: PlaybackItem) async { loadedItems.append(item) }
    func play() { playCount += 1 }
    func pause() { pauseCount += 1 }
    func stop() {}
    func seek(to seconds: TimeInterval) async { seekedTo.append(seconds) }
    func setVolume(_ volume: Float) {}
    func setRate(_ rate: Float) {}
    func select(track: MediaTrack) { selectedTracks.append(track) }
    func makeVideoView() -> UIView { UIView() }

    func teardown() {
        didTeardown = true
        continuation.finish()
    }
}

/// Bellekte tutan ilerleme deposu.
///
/// `@unchecked Sendable`: protokol `Sendable` istiyor ama testler tek
/// iş parçacığında koşuyor; gerçek eşzamanlılık koruması gereksiz.
final class TestProgressRepository: PlaybackProgressRepository, @unchecked Sendable {

    var stored: [String: PlaybackProgress] = [:]
    private(set) var saveCount = 0

    func progress(for source: PlaybackItem.Source) async throws -> PlaybackProgress? {
        stored[source.storageKey]
    }

    func save(_ progress: PlaybackProgress, for source: PlaybackItem.Source) async throws {
        stored[source.storageKey] = progress
        saveCount += 1
    }

    func continueWatching(playlistID: Playlist.ID, limit: Int) async throws -> [PlaybackProgress] {
        Array(stored.values.prefix(limit))
    }

    func clear(for source: PlaybackItem.Source) async throws {
        stored[source.storageKey] = nil
    }

    func clearAll() async throws { stored = [:] }
}

/// Bellekte tutan izleme geçmişi.
final class TestHistoryRepository: WatchHistoryRepository, @unchecked Sendable {

    private(set) var recorded: [(source: PlaybackItem.Source, date: Date)] = []

    func record(_ source: PlaybackItem.Source, at date: Date) async throws {
        recorded.append((source, date))
    }

    func recentChannels(playlistID: Playlist.ID, limit: Int) async throws -> [Channel] { [] }
    func clearAll() async throws { recorded = [] }
}
