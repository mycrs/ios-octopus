import OctopusDomain
import OctopusPlayback

public struct PlayerDependencies {
    public let resolver: PlaybackEngineResolver
    public let streams: StreamResolving
    public let progress: PlaybackProgressRepository
    public let history: WatchHistoryRepository
    public let channels: ChannelRepository
    public let vod: VODRepository
    public let series: SeriesRepository
    public let epg: EPGRepository?

    /// Oynatıcıdaki kanal yolları da ebeveyn filtresinden geçer.
    public let parental: ParentalControlling
    public let preferences: PlaybackPreferences?

    public init(
        resolver: PlaybackEngineResolver,
        streams: StreamResolving,
        progress: PlaybackProgressRepository,
        history: WatchHistoryRepository,
        channels: ChannelRepository,
        vod: VODRepository,
        series: SeriesRepository,
        epg: EPGRepository? = nil,
        preferences: PlaybackPreferences? = nil,
        parental: ParentalControlling = OpenParentalControl()
    ) {
        self.resolver = resolver
        self.streams = streams
        self.progress = progress
        self.history = history
        self.channels = channels
        self.vod = vod
        self.series = series
        self.epg = epg
        self.preferences = preferences
        self.parental = parental
    }
}
