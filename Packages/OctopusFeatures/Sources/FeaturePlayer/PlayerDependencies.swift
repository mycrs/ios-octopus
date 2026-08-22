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

    /// Canlı TV'deki mini oynatıcıyla **paylaşılan** denetleyici.
    ///
    /// ⚠️ Paylaşım şart: ayrı örneklerle tam ekrana geçmek motoru bırakıp
    /// yeniden bağlanmak demekti; kullanıcı her geçişte birkaç saniye
    /// siyah ekran görüyordu. Tek örnekle yayın kesintisiz devam eder.
    public let controller: PlayerController

    public init(
        resolver: PlaybackEngineResolver,
        streams: StreamResolving,
        progress: PlaybackProgressRepository,
        history: WatchHistoryRepository,
        channels: ChannelRepository,
        vod: VODRepository,
        series: SeriesRepository,
        controller: PlayerController,
        epg: EPGRepository? = nil,
        preferences: PlaybackPreferences? = nil,
        parental: ParentalControlling = OpenParentalControl()
    ) {
        self.controller = controller
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
