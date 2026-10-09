import Foundation
import OctopusDomain

/// Recovery depends on the failure's cause, never on a localized message.
public enum PlaybackFailureKind: String, Sendable {
    case authorization
    case missingResource
    case network
    case decoder
    case unsupportedFormat
    case videoNotRendered
    case requiresFallbackHeaders
    case unsupportedHeaders
    case unknown

    var remembersFallback: Bool {
        self == .decoder || self == .videoNotRendered
    }
}

struct PlaybackRecoveryPolicy {
    enum Action: Equatable {
        case stop
        case retryCurrent
        case tryFallback
    }

    static func action(for error: AppError, kind: PlaybackFailureKind) -> Action {
        switch kind {
        case .authorization, .missingResource, .unsupportedHeaders:
            return .stop
        case .network:
            return .retryCurrent
        case .decoder, .unsupportedFormat, .videoNotRendered, .requiresFallbackHeaders:
            return .tryFallback
        case .unknown:
            switch error {
            case .unauthorized, .subscriptionUnavailable, .connectionLimitReached, .notFound, .storage:
                return .stop
            case .network:
                return .retryCurrent
            case .playbackFailed, .invalidResponse, .unknown:
                // Older/custom engines may not provide a category. One compatibility
                // fallback remains available, but this never creates a remembered rule.
                return .tryFallback
            }
        }
    }
}
