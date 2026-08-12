import OctopusDomain

extension SyncContentCounts {

    mutating func record(_ stage: SyncStage) {
        switch stage {
        case .fetchingChannels(let done, let total) where total != nil:
            channels = done
        case .fetchingMovies(let done, let total) where total != nil:
            movies = done
        case .fetchingSeries(let done, let total) where total != nil:
            series = done
        case .finished(_, let finalCounts):
            self = finalCounts
        default:
            break
        }
    }
}
