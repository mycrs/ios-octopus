import Foundation
import OctopusDomain

/// Explicit consent lasts only as long as this player presentation.
struct NextEpisodeSession {
    enum Action: Equatable {
        case none
        case showPrompt
        case playNext
    }

    private(set) var automaticallyAdvance = false
    private var handledEpisodes: Set<Episode.ID> = []

    mutating func reachedEnd(source: PlaybackItem.Source, hasNext: Bool) -> Action {
        guard case .episode(let episodeID) = source, hasNext,
              handledEpisodes.insert(episodeID).inserted
        else { return .none }
        return automaticallyAdvance ? .playNext : .showPrompt
    }

    mutating func enableAutomaticAdvance() {
        automaticallyAdvance = true
    }
}
