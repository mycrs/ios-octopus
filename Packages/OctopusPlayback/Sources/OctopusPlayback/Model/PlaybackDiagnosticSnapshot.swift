import Foundation
import OctopusDomain

/// Destek raporunun izinli alanları. İçerik kimliği, URL ve ham hata taşımaz.
public struct PlaybackDiagnosticSnapshot: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable {
        case idle, loading, buffering, playing, paused, ended, failed
    }
    public enum Failure: String, Codable, Sendable {
        case network, unauthorized, connectionLimit, invalidResponse, storage, playback, notFound, unknown
    }
    public let capturedAt: Date
    public let engine: PlaybackEngineResolver.Decision?
    public let state: State
    public let failure: Failure?
    public let format: StreamFormat?
    public let isLive: Bool?
    public let firstVideoFrameReady: Bool?
    public let audioTrackCount: Int
    public let subtitleTrackCount: Int
    public let supportsAirPlay: Bool
    public let pictureInPictureAvailable: Bool
    public let fallbackAttempted: Bool
    public let fallbackAvailable: Bool
    public let reconnectAttempt: Int

    init(
        capturedAt: Date, engine: PlaybackEngineResolver.Decision?, state: PlaybackState,
        format: StreamFormat?, isLive: Bool?, firstVideoFrameReady: Bool?,
        audioTrackCount: Int, subtitleTrackCount: Int, supportsAirPlay: Bool,
        pictureInPictureAvailable: Bool, fallbackAttempted: Bool, reconnectAttempt: Int,
        fallbackAvailable: Bool = false
    ) {
        self.capturedAt = capturedAt
        self.engine = engine
        if case .failed(let error) = state {
            switch error {
            case .network: self.failure = .network
            case .unauthorized: self.failure = .unauthorized
            case .connectionLimitReached: self.failure = .connectionLimit
            case .invalidResponse: self.failure = .invalidResponse
            case .storage: self.failure = .storage
            case .playbackFailed: self.failure = .playback
            case .notFound: self.failure = .notFound
            case .unknown: self.failure = .unknown
            }
        } else {
            self.failure = nil
        }
        switch state {
        case .idle: self.state = .idle
        case .loading: self.state = .loading
        case .buffering: self.state = .buffering
        case .playing: self.state = .playing
        case .paused: self.state = .paused
        case .ended: self.state = .ended
        case .failed: self.state = .failed
        }
        self.format = format
        self.isLive = isLive
        self.firstVideoFrameReady = firstVideoFrameReady
        self.audioTrackCount = audioTrackCount
        self.subtitleTrackCount = subtitleTrackCount
        self.supportsAirPlay = supportsAirPlay
        self.pictureInPictureAvailable = pictureInPictureAvailable
        self.fallbackAttempted = fallbackAttempted
        self.fallbackAvailable = fallbackAvailable
        self.reconnectAttempt = reconnectAttempt
    }
}
