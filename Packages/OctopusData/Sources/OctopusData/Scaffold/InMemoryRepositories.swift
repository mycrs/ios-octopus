import Foundation
import OctopusDomain

// 🚧 GEÇİCİ İSKELE — Faz 1-2'de GRDB destekli gerçek implementasyonlarla değişecek.
//
// Neden şimdi yazıldı?
// 1. Uygulama BUGÜN derlenip çalışsın; mimari uçtan uca doğrulanabilsin.
// 2. Bu tipler kalıcı olarak SwiftUI Preview ve birim testlerinde sahte veri
//    kaynağı olarak kullanılacak — silinmeyecek, `Preview` hedefine taşınacak.
//
// Hepsi `actor`: eşzamanlı erişimde veri yarışı olmaz ve gerçek implementasyonun
// eşzamanlılık davranışını şimdiden taklit eder.

public actor InMemoryPlaylistRepository: PlaylistRepository {

    private var storage: [Playlist]

    public init(seed: [Playlist] = []) {
        self.storage = seed
    }

    public func all() async throws -> [Playlist] { storage }

    public func playlist(id: Playlist.ID) async throws -> Playlist? {
        storage.first { $0.id == id }
    }

    public func activePlaylist() async throws -> Playlist? {
        storage.first { $0.isActive }
    }

    public func add(_ playlist: Playlist, password: String?) async throws {
        storage.append(playlist)
    }

    public func update(_ playlist: Playlist) async throws {
        guard let index = storage.firstIndex(where: { $0.id == playlist.id }) else {
            throw AppError.notFound
        }
        storage[index] = playlist
    }

    public func setActive(id: Playlist.ID) async throws {
        for index in storage.indices {
            storage[index].isActive = (storage[index].id == id)
        }
    }

    public func delete(id: Playlist.ID) async throws {
        storage.removeAll { $0.id == id }
    }

    public func validate(_ playlist: Playlist, password: String?) async throws -> ProviderAccount {
        throw AppError.unknown(reason: "Kaynak doğrulama Faz 2'de eklenecek")
    }
}

public actor InMemoryChannelRepository: ChannelRepository {

    // Not: depolama alanı `storedChannels`, protokol metodu `channels(...)`.
    // Aynı ada sahip olsalardı actor içindeki çağrılar belirsizleşirdi.
    private var storedChannels: [Channel]
    private var storedCategories: [MediaCategory]

    public init(channels: [Channel] = [], categories: [MediaCategory] = []) {
        self.storedChannels = channels
        self.storedCategories = categories
    }

    public func categories(playlistID: Playlist.ID) async throws -> [MediaCategory] {
        storedCategories.filter { $0.playlistID == playlistID && $0.kind == .live }
    }

    public func channels(
        playlistID: Playlist.ID,
        categoryID: MediaCategory.ID?
    ) async throws -> [Channel] {
        storedChannels.filter {
            $0.playlistID == playlistID && (categoryID == nil || $0.categoryID == categoryID)
        }
    }

    public func channel(id: Channel.ID) async throws -> Channel? {
        storedChannels.first { $0.id == id }
    }

    public func search(
        query: String,
        playlistID: Playlist.ID,
        limit: Int
    ) async throws -> [Channel] {
        storedChannels
            .filter { $0.playlistID == playlistID && $0.name.localizedCaseInsensitiveContains(query) }
            .prefix(limit)
            .map { $0 }
    }

    public nonisolated func observeChannels(
        playlistID: Playlist.ID,
        categoryID: MediaCategory.ID?
    ) -> AsyncStream<[Channel]> {
        AsyncStream { continuation in
            Task {
                let snapshot = try? await self.channels(playlistID: playlistID, categoryID: categoryID)
                continuation.yield(snapshot ?? [])
                continuation.finish()
            }
        }
    }
}

public actor InMemoryVODRepository: VODRepository {

    private var storedMovies: [Movie]
    private var storedCategories: [MediaCategory]

    public init(movies: [Movie] = [], categories: [MediaCategory] = []) {
        self.storedMovies = movies
        self.storedCategories = categories
    }

    public func categories(playlistID: Playlist.ID) async throws -> [MediaCategory] {
        storedCategories.filter { $0.playlistID == playlistID && $0.kind == .movie }
    }

    public func movies(
        playlistID: Playlist.ID,
        categoryID: MediaCategory.ID?,
        limit: Int,
        offset: Int
    ) async throws -> [Movie] {
        let filtered = storedMovies.filter {
            $0.playlistID == playlistID && (categoryID == nil || $0.categoryID == categoryID)
        }
        return Array(filtered.dropFirst(offset).prefix(limit))
    }

    public func movie(id: Movie.ID) async throws -> Movie? {
        storedMovies.first { $0.id == id }
    }

    public func loadDetails(id: Movie.ID) async throws -> Movie {
        guard let movie = storedMovies.first(where: { $0.id == id }) else { throw AppError.notFound }
        return movie
    }

    public func search(query: String, playlistID: Playlist.ID, limit: Int) async throws -> [Movie] {
        storedMovies
            .filter { $0.playlistID == playlistID && $0.title.localizedCaseInsensitiveContains(query) }
            .prefix(limit)
            .map { $0 }
    }

    public func recentlyAdded(playlistID: Playlist.ID, limit: Int) async throws -> [Movie] {
        storedMovies
            .filter { $0.playlistID == playlistID }
            .sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
            .prefix(limit)
            .map { $0 }
    }
}

public actor InMemorySeriesRepository: SeriesRepository {

    private var allSeries: [Series]
    private var allSeasons: [Season]
    private var allEpisodes: [Episode]
    private var storedCategories: [MediaCategory]

    public init(
        series: [Series] = [],
        seasons: [Season] = [],
        episodes: [Episode] = [],
        categories: [MediaCategory] = []
    ) {
        self.allSeries = series
        self.allSeasons = seasons
        self.allEpisodes = episodes
        self.storedCategories = categories
    }

    public func categories(playlistID: Playlist.ID) async throws -> [MediaCategory] {
        storedCategories.filter { $0.playlistID == playlistID && $0.kind == .series }
    }

    public func series(
        playlistID: Playlist.ID,
        categoryID: MediaCategory.ID?,
        limit: Int,
        offset: Int
    ) async throws -> [Series] {
        let filtered = allSeries.filter {
            $0.playlistID == playlistID && (categoryID == nil || $0.categoryID == categoryID)
        }
        return Array(filtered.dropFirst(offset).prefix(limit))
    }

    public func series(id: Series.ID) async throws -> Series? {
        allSeries.first { $0.id == id }
    }

    public func seasons(seriesID: Series.ID) async throws -> [Season] {
        allSeasons.filter { $0.seriesID == seriesID }.sorted { $0.number < $1.number }
    }

    public func episodes(seriesID: Series.ID, seasonNumber: Int) async throws -> [Episode] {
        allEpisodes
            .filter { $0.seriesID == seriesID && $0.seasonNumber == seasonNumber }
            .sorted { $0.number < $1.number }
    }

    public func episode(id: Episode.ID) async throws -> Episode? {
        allEpisodes.first { $0.id == id }
    }

    public func loadDetails(id: Series.ID) async throws {}

    public func search(query: String, playlistID: Playlist.ID, limit: Int) async throws -> [Series] {
        allSeries
            .filter { $0.playlistID == playlistID && $0.title.localizedCaseInsensitiveContains(query) }
            .prefix(limit)
            .map { $0 }
    }
}

public actor InMemoryEPGRepository: EPGRepository {

    private var storedPrograms: [EPGProgram]

    public init(programs: [EPGProgram] = []) {
        self.storedPrograms = programs
    }

    public func nowPlaying(epgChannelID: String, at date: Date) async throws -> EPGProgram? {
        storedPrograms.first { $0.epgChannelID == epgChannelID && $0.isOnAir(at: date) }
    }

    public func nowPlaying(
        epgChannelIDs: [String],
        at date: Date
    ) async throws -> [String: EPGProgram] {
        let wanted = Set(epgChannelIDs)
        var result: [String: EPGProgram] = [:]
        for program in storedPrograms
        where wanted.contains(program.epgChannelID) && program.isOnAir(at: date) {
            result[program.epgChannelID] = program
        }
        return result
    }

    public func programs(
        epgChannelID: String,
        from: Date,
        to: Date
    ) async throws -> [EPGProgram] {
        storedPrograms
            .filter { $0.epgChannelID == epgChannelID && $0.endDate > from && $0.startDate < to }
            .sorted { $0.startDate < $1.startDate }
    }

    public func purgePrograms(before date: Date) async throws {
        storedPrograms.removeAll { $0.endDate < date }
    }
}

public actor InMemoryFavoritesRepository: FavoritesRepository {

    private var keys: Set<String> = []

    public init() {}

    public func isFavorite(_ source: PlaybackItem.Source) async throws -> Bool {
        keys.contains(source.storageKey)
    }

    public func toggle(_ source: PlaybackItem.Source) async throws -> Bool {
        let key = source.storageKey
        if keys.contains(key) {
            keys.remove(key)
            return false
        }
        keys.insert(key)
        return true
    }

    public func favoriteChannels(playlistID: Playlist.ID) async throws -> [Channel] { [] }
    public func favoriteMovies(playlistID: Playlist.ID) async throws -> [Movie] { [] }
    public func favoriteSeries(playlistID: Playlist.ID) async throws -> [Series] { [] }

    private func snapshot() -> Set<String> { keys }

    public nonisolated func observeFavoriteKeys() -> AsyncStream<Set<String>> {
        AsyncStream { continuation in
            Task {
                continuation.yield(await self.snapshot())
                continuation.finish()
            }
        }
    }
}

public actor InMemoryPlaybackProgressRepository: PlaybackProgressRepository {

    private var storage: [String: PlaybackProgress] = [:]

    public init() {}

    public func progress(for source: PlaybackItem.Source) async throws -> PlaybackProgress? {
        storage[source.storageKey]
    }

    public func save(
        _ progress: PlaybackProgress,
        for source: PlaybackItem.Source
    ) async throws {
        storage[source.storageKey] = progress
    }

    public func continueWatching(
        playlistID: Playlist.ID,
        limit: Int
    ) async throws -> [PlaybackProgress] {
        storage.values
            .filter { !$0.isFinished }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map { $0 }
    }

    public func clear(for source: PlaybackItem.Source) async throws {
        storage[source.storageKey] = nil
    }

    public func clearAll() async throws {
        storage.removeAll()
    }
}

public actor InMemoryWatchHistoryRepository: WatchHistoryRepository {

    private var entries: [(key: String, date: Date)] = []

    public init() {}

    public func record(_ source: PlaybackItem.Source, at date: Date) async throws {
        entries.removeAll { $0.key == source.storageKey }
        entries.append((source.storageKey, date))
    }

    public func recentChannels(playlistID: Playlist.ID, limit: Int) async throws -> [Channel] { [] }

    public func clearAll() async throws {
        entries.removeAll()
    }
}

/// 🚧 Faz 2'de gerçek URL kurucularla değişecek.
public struct ScaffoldStreamResolver: StreamResolving {

    public init() {}

    public func playbackItem(for channel: Channel) async throws -> PlaybackItem {
        throw AppError.playbackFailed(reason: "Akış adresi çözümleme Faz 2'de eklenecek")
    }

    public func playbackItem(for movie: Movie) async throws -> PlaybackItem {
        throw AppError.playbackFailed(reason: "Akış adresi çözümleme Faz 2'de eklenecek")
    }

    public func playbackItem(for episode: Episode, in series: Series) async throws -> PlaybackItem {
        throw AppError.playbackFailed(reason: "Akış adresi çözümleme Faz 2'de eklenecek")
    }
}

/// 🚧 Faz 2'de gerçek senkronizasyonla değişecek.
public struct ScaffoldContentSync: ContentSyncing {

    public init() {}

    public func sync(playlistID: Playlist.ID) async throws {
        throw AppError.unknown(reason: "Senkronizasyon Faz 2'de eklenecek")
    }

    public func syncEPG(playlistID: Playlist.ID) async throws {
        throw AppError.unknown(reason: "EPG senkronizasyonu Faz 6'da eklenecek")
    }

    public func observeProgress(playlistID: Playlist.ID) -> AsyncStream<SyncStage> {
        AsyncStream { continuation in
            continuation.yield(.idle)
            continuation.finish()
        }
    }
}
