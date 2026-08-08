import Foundation
import UIKit
import OctopusDomain

/// 🚧 GEÇİCİ İSKELE — Faz 5'te `AVPlayerEngine` ile değiştirilecek.
///
/// Amacı: motor sözleşmesi hazırken uygulamanın **bugün derlenip çalışması**.
/// Hiçbir şey oynatmaz; yüklenen içeriği loglar ve "açılamadı" durumuna geçer.
///
/// Bu yer tutucu sayesinde `AppContainer`, `PlayerScreen` ve resolver zinciri
/// gerçek motorlar yazılmadan önce uçtan uca doğrulanabilir.
@MainActor
public final class NullPlaybackEngine: PlaybackEngine {

    public let identifier: String
    public let events: AsyncStream<PlaybackEvent>

    private let continuation: AsyncStream<PlaybackEvent>.Continuation

    public private(set) var currentState: PlaybackState = .idle
    public private(set) var audioTracks: [MediaTrack] = []
    public private(set) var subtitleTracks: [MediaTrack] = []
    public let selectedAudioTrack: MediaTrack? = nil
    public let selectedSubtitleTrack: MediaTrack? = nil
    public let supportsPictureInPicture = false

    public init(identifier: String = "null") {
        self.identifier = identifier
        var capturedContinuation: AsyncStream<PlaybackEvent>.Continuation!
        self.events = AsyncStream { capturedContinuation = $0 }
        self.continuation = capturedContinuation
    }

    public func load(_ item: PlaybackItem) async {
        transition(to: .loading)
        transition(to: .failed(.playbackFailed(
            reason: "Oynatma motoru henüz bağlanmadı (Faz 5). İstenen: \(item.format.rawValue)"
        )))
    }

    public func play() {}
    public func pause() {}

    public func stop() {
        transition(to: .idle)
    }

    public func seek(to seconds: TimeInterval) async {}
    public func setVolume(_ volume: Float) {}
    public func setRate(_ rate: Float) {}
    public func select(track: MediaTrack) {}

    public func makeVideoView() -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        return view
    }

    public func teardown() {
        continuation.finish()
    }

    private func transition(to state: PlaybackState) {
        currentState = state
        continuation.yield(.stateChanged(state))
    }
}
