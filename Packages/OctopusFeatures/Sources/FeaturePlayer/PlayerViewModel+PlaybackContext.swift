import Foundation
import OctopusDomain
import OctopusDesignSystem

extension PlayerViewModel {

    /// Bölüm sırasını yalnızca gerektiğinde hazırlar. Sonraki sezon varsa ilk
    /// bölümüne geçer; son bölümde kart gösterilmez.
    func prepareEpisodeContext() async {
        let generation = selectionGeneration
        let requestedSource = source
        guard
            case .episode(let id) = source,
            let current = try? await dependencies.series.episode(id: id)
        else {
            guard isCurrentSelection(generation, source: requestedSource) else { return }
            nextEpisode = nil
            return
        }

        let seasons = (try? await dependencies.series.seasons(seriesID: current.seriesID)) ?? []
        let seasonNumbers = Set(seasons.map(\.number) + [current.seasonNumber]).sorted()

        var candidates: [Episode] = []
        for seasonNumber in seasonNumbers where seasonNumber >= current.seasonNumber {
            candidates += (try? await dependencies.series.episodes(
                seriesID: current.seriesID,
                seasonNumber: seasonNumber
            )) ?? []
        }
        guard isCurrentSelection(generation, source: requestedSource) else { return }
        nextEpisode = Self.followingEpisode(after: current, in: candidates)
    }

    public func playNextEpisode() async {
        guard let nextEpisode else { return }
        source = .episode(nextEpisode.id)

        await resolveSelection(updateZapping: true)
    }

    /// Canlı panelden doğrudan kanal seçimi. Liste ebeveyn filtresinden geçmiş
    /// `zapList` olduğu için kilit bu giriş yolundan da atlanamaz.
    public func play(channel: Channel) async {
        guard zapList.contains(where: { $0.id == channel.id }) else { return }
        source = .liveChannel(channel.id)

        await resolveSelection()
    }

    func prepareLiveGuide(now: Date = Date()) async {
        let generation = selectionGeneration
        let requestedSource = source
        guard
            case .liveChannel(let id) = source,
            let epg = dependencies.epg,
            let channel = try? await dependencies.channels.channel(id: id),
            let epgID = channel.epgChannelID
        else {
            guard isCurrentSelection(generation, source: requestedSource) else { return }
            currentProgram = nil
            followingProgram = nil
            return
        }

        let programs = (try? await epg.programs(
            playlistID: channel.playlistID,
            epgChannelID: epgID,
            from: now.addingTimeInterval(-3_600),
            to: now.addingTimeInterval(12 * 3_600)
        )) ?? []

        guard isCurrentSelection(generation, source: requestedSource) else { return }
        let guide = Self.guidePrograms(at: now, programs: programs)
        currentProgram = guide.current
        followingProgram = guide.following
    }

    static func followingEpisode(after current: Episode, in episodes: [Episode]) -> Episode? {
        episodes
            .filter {
                $0.seasonNumber > current.seasonNumber
                    || ($0.seasonNumber == current.seasonNumber && $0.number > current.number)
            }
            .sorted {
                if $0.seasonNumber == $1.seasonNumber {
                    if $0.number == $1.number { return $0.id.value < $1.id.value }
                    return $0.number < $1.number
                }
                return $0.seasonNumber < $1.seasonNumber
            }
            .first
    }

    static func guidePrograms(
        at date: Date,
        programs: [EPGProgram]
    ) -> (current: EPGProgram?, following: EPGProgram?) {
        let current = programs.first(where: { $0.isOnAir(at: date) })
        let following = programs
            .filter { $0.startDate >= (current?.endDate ?? date) }
            .sorted { $0.startDate < $1.startDate }
            .first
        return (current, following)
    }
}
