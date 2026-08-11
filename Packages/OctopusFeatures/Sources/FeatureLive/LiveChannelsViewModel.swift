import Foundation
import Combine
import OctopusDomain
import OctopusDesignSystem

/// Canlı TV listesi: kategoriler, kanallar, arama ve favoriler.
@MainActor
public final class LiveChannelsViewModel: ObservableObject {

    @Published public private(set) var categories: [MediaCategory] = []
    @Published public private(set) var channels: [Channel] = []
    @Published public private(set) var favoriteKeys: Set<String> = []
    @Published public private(set) var state: LoadableState<Int> = .idle

    /// Kanal kimliğine göre o an yayında olan program.
    @Published public private(set) var nowPlaying: [String: EPGProgram] = [:]
    /// İlerleme çubuklarının canlı görünmesi için kullanılan referans an.
    @Published public private(set) var clock = Date()

    /// Son izlenen kanal — hiçbir şey oynatılmıyorken tepede onun afişi durur.
    @Published public private(set) var lastWatchedChannel: Channel?

    /// Gömülü mini oynatıcıda **şu an** oynayan kanal. `nil` = henüz yok.
    ///
    /// Referanstaki davranış: listeden bir kanala dokunmak tam ekrana
    /// atlamaz, yayını buradan başlatır ve kullanıcı listede gezinmeye
    /// devam eder.
    @Published public private(set) var playingChannel: Channel?

    /// Akış adresi çözülemediğinde gösterilecek mesaj.
    ///
    /// ⚠️ Liste `state`'ini bozmuyor: tek bir kanal açılmadı diye tüm
    /// kanal listesini hata ekranıyla değiştirmek orantısız olurdu.
    @Published public private(set) var playbackMessage: String?

    /// `nil` = tüm kanallar.
    @Published public private(set) var selectedCategoryID: MediaCategory.ID?
    @Published public var searchText = "" {
        didSet { scheduleSearch() }
    }

    /// Arama sonuçları listeyi geçici olarak değiştirir; temizlenince
    /// kullanıcı kaldığı kategoriye döner.
    public private(set) var isSearching = false

    private let dependencies: LiveDependencies
    private let searchDebounce: Duration

    private var activePlaylistID: Playlist.ID?
    /// Kilit kurulu ve açılmamışsa yetişkin kanallar süzülür.
    private var parentalFilter = ParentalFilter.open
    private var searchTask: Task<Void, Never>?
    private var observationTask: Task<Void, Never>?
    private var favoritesTask: Task<Void, Never>?
    private var epgTask: Task<Void, Never>?
    private let epgRefreshInterval: Duration

    public init(
        dependencies: LiveDependencies,
        // Kullanıcı yazarken her tuşta sorgu atmak büyük kataloglarda
        // arayüzü kilitliyor. Referans projede bu değer 600 ms'e çekilmişti.
        searchDebounce: Duration = .milliseconds(300),
        // Program değişimlerini yakalamak için yeterli; daha sık tazelemek
        // listeyi gereksiz yere yeniden çizer.
        epgRefreshInterval: Duration = .seconds(60)
    ) {
        self.dependencies = dependencies
        self.searchDebounce = searchDebounce
        self.epgRefreshInterval = epgRefreshInterval
    }

    deinit {
        searchTask?.cancel()
        observationTask?.cancel()
        favoritesTask?.cancel()
        epgTask?.cancel()
    }

    // MARK: - Yükleme

    public func load() async {
        if channels.isEmpty { state = .loading }

        do {
            guard let playlist = try await dependencies.playlists.activePlaylist() else {
                // Kaynak yoksa boş liste doğru davranış; hata değil.
                state = .loaded(0)
                channels = []
                categories = []
                return
            }
            activePlaylistID = playlist.id
            await refreshParentalFilter()

            let allCategories = try await dependencies.channels.categories(
                playlistID: playlist.id
            )
            categories = parentalFilter.filter(allCategories)
            dropSelectionIfHidden()
            observeChannels(playlistID: playlist.id, categoryID: selectedCategoryID)
            observeFavorites()
            startEPGRefresh()
            await refreshLastWatched(playlistID: playlist.id)
        } catch {
            state = .failed(AppError.wrap(error))
        }
    }

    /// Kategori değişimi.
    ///
    /// ⚠️ Liste dolu iken `.loading` durumuna geçilmiyor: referans projede
    /// bu, her kategori geçişinde spinner parlamasına ve kaydırma konumunun
    /// sıfırlanmasına yol açmıştı.
    public func selectCategory(_ id: MediaCategory.ID?) {
        guard selectedCategoryID != id else { return }
        Haptics.selection()
        selectedCategoryID = id
        clearSearch()

        guard let playlistID = activePlaylistID else { return }
        observeChannels(playlistID: playlistID, categoryID: id)
    }

    // MARK: - Arama

    private func scheduleSearch() {
        searchTask?.cancel()

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            // Arama temizlendi: kullanıcı kaldığı kategoriye dönmeli.
            if isSearching {
                isSearching = false
                if let playlistID = activePlaylistID {
                    observeChannels(playlistID: playlistID, categoryID: selectedCategoryID)
                }
            }
            return
        }

        searchTask = Task { [weak self, searchDebounce] in
            try? await Task.sleep(for: searchDebounce)
            guard let self, !Task.isCancelled else { return }
            await self.performSearch(query)
        }
    }

    private func performSearch(_ query: String) async {
        guard let playlistID = activePlaylistID else { return }

        // Arama sonuçları canlı gözlemin üzerine yazar; gözlem durdurulur
        // ki senkronizasyon sonuçları arama listesini ezmesin.
        observationTask?.cancel()
        isSearching = true

        do {
            let results = try await dependencies.channels.search(
                query: query,
                playlistID: playlistID,
                limit: 200
            )
            guard !Task.isCancelled else { return }

            // Arama sonuçları da süzülür; aksi halde kilit aramayla atlatılırdı.
            var allowed = parentalFilter.filter(results)

            // Numara yazıldıysa o kanal en üste alınır.
            if let match = try await numberMatch(for: query, playlistID: playlistID) {
                allowed.removeAll { $0.id == match.id }
                allowed.insert(match, at: 0)
            }

            guard !Task.isCancelled else { return }
            channels = allowed
            state = .loaded(allowed.count)
        } catch {
            state = .failed(AppError.wrap(error))
        }
    }

    /// Sorgu bir kanal numarasıysa o kanalı bulur.
    ///
    /// IPTV kullanıcıları kanalları numarayla hatırlıyor ("205'e geç").
    /// Ad araması bunu karşılamıyor: "205" yazınca FTS **adında** 205 geçen
    /// kanalları buluyor, 205 numaralı kanalı değil. İkisi birleştiriliyor —
    /// numara eşleşmesi üstte, ad eşleşmeleri altında.
    ///
    /// Kilitli yetişkin kanal numarayla da açılmamalı: süzgeçten geçiriliyor.
    private func numberMatch(
        for query: String,
        playlistID: Playlist.ID
    ) async throws -> Channel? {
        guard let number = Int(query), number > 0 else { return nil }

        guard let channel = try await dependencies.channels.channel(
            number: number,
            playlistID: playlistID
        ) else { return nil }

        return parentalFilter.allows(channel: channel) ? channel : nil
    }

    /// Kilit durumu değişmiş olabilir (Ayarlar'dan açılıp kapanabiliyor).
    public func refreshParentalFilter() async {
        parentalFilter = await .current(dependencies.parental)
    }

    /// Üstteki önizleme kartını doldurur.
    ///
    /// ⚠️ Kilitli yetişkin kanal önizlemede de görünmemeli — kilidi
    /// atlatmanın bir başka yolu olurdu, aynen numarayla aramada olduğu gibi.
    private func refreshLastWatched(playlistID: Playlist.ID) async {
        guard let recent = try? await dependencies.history.recentChannels(
            playlistID: playlistID,
            limit: 1
        ).first else {
            lastWatchedChannel = nil
            return
        }
        lastWatchedChannel = parentalFilter.allows(channel: recent) ? recent : nil
    }

    /// Seçili kategori az önce gizlendiyse "Tümü"ne dön.
    ///
    /// Kullanıcı yetişkin bir kategoride dururken kilidi kurmuş olabilir;
    /// seçim orada kalırsa liste kalıcı olarak boş görünür.
    private func dropSelectionIfHidden() {
        guard let selected = selectedCategoryID else { return }
        if !categories.contains(where: { $0.id == selected }) {
            selectedCategoryID = nil
        }
    }

    public func clearSearch() {
        searchTask?.cancel()
        searchText = ""
        isSearching = false
    }

    // MARK: - Gömülü oynatma

    /// Kanalın oynatılabilir adresini çözer.
    ///
    /// ⚠️ Motoru burada **başlatmıyoruz**: `PlayerController` görünümün
    /// ömrüne bağlı (`@StateObject`) ve ViewModel onu tutmamalı — aksi
    /// hâlde ekran kapandığında motor bırakılmaz ve IPTV bağlantı kotası
    /// dolar (bkz. `PlaybackEngine.teardown`).
    public func playbackItem(for channel: Channel) async -> PlaybackItem? {
        // Kilitli kanal gömülü oynatıcıda da açılmamalı; liste süzülüyor
        // ama numarayla arama gibi yollarla buraya düşebilir.
        guard parentalFilter.allows(channel: channel) else {
            playbackMessage = "Bu içerik koruma nedeniyle gizli."
            return nil
        }

        do {
            let item = try await dependencies.streams.playbackItem(for: channel)
            playingChannel = channel
            playbackMessage = nil
            return item
        } catch {
            playbackMessage = AppError.wrap(error).userMessage
            return nil
        }
    }

    /// Mini oynatıcı durdurulduğunda çağrılır.
    public func clearPlayingChannel() {
        playingChannel = nil
    }

    // MARK: - Favoriler

    public func toggleFavorite(_ channel: Channel) async {
        do {
            let added = try await dependencies.favorites.toggle(.channel(channel.id))
            // Eklemek onaylanır, çıkarmak hafifçe hissedilir.
            if added { Haptics.success() } else { Haptics.light() }
        } catch {
            state = .failed(AppError.wrap(error))
        }
    }

    public func isFavorite(_ channel: Channel) -> Bool {
        favoriteKeys.contains(FavoriteTarget.channel(channel.id).storageKey)
    }

    // MARK: - Gözlem
    //
    // Senkronizasyon veritabanına yazdıkça liste kendini tazeler;
    // kullanıcı "yenile" demek zorunda kalmaz.

    private func observeChannels(playlistID: Playlist.ID, categoryID: MediaCategory.ID?) {
        observationTask?.cancel()
        observationTask = Task { [weak self, dependencies] in
            for await updated in dependencies.channels.observeChannels(
                playlistID: playlistID,
                categoryID: categoryID
            ) {
                guard let self, !Task.isCancelled else { return }
                // Arama sürerken gelen güncelleme sonuçları ezmemeli.
                guard !self.isSearching else { continue }

                let allowed = self.parentalFilter.filter(updated)
                self.channels = allowed
                self.state = .loaded(allowed.count)
            }
        }
    }

    /// Şu an oynayan programları periyodik tazeler.
    ///
    /// ⚠️ Kanal kimliklerini tek tek sormak yerine zaman aralığıyla **tek
    /// sorgu** yapılır: 20.000 kimlik içeren bir `IN` sorgusu hem yavaş
    /// hem de SQLite değişken sınırına takılır.
    private func startEPGRefresh() {
        epgTask?.cancel()
        epgTask = Task { [weak self, dependencies, epgRefreshInterval] in
            while !Task.isCancelled {
                let current = Date()
                let programs = (try? await dependencies.epg.allNowPlaying(at: current)) ?? [:]

                guard let self, !Task.isCancelled else { return }
                self.nowPlaying = programs
                self.clock = current

                try? await Task.sleep(for: epgRefreshInterval)
            }
        }
    }

    /// "32 dk" / "1 sa 5 dk" — kalan sürenin okunur hâli.
    ///
    /// Kural Domain'de (`EPGProgram.remaining`), biçim burada: satır
    /// görünümü `private` olduğu için test edilebilir bir yerde durmalı.
    static func remainingText(_ program: EPGProgram, at date: Date) -> String? {
        guard let remaining = program.remaining(at: date) else { return nil }

        let minutes = Int(remaining / 60)
        // Bir dakikanın altını "0 dk" diye yazmak yerine gizle: program
        // bitmek üzere ve sayı saniyede bir değişip dikkat dağıtır.
        guard minutes >= 1 else { return nil }

        if minutes < 60 { return "\(minutes) dk" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) sa" : "\(hours) sa \(rest) dk"
    }

    /// Bir kanalın o anki programı.
    public func currentProgram(for channel: Channel) -> EPGProgram? {
        guard let epgID = channel.epgChannelID else { return nil }
        return nowPlaying[epgID]
    }

    private func observeFavorites() {
        favoritesTask?.cancel()
        favoritesTask = Task { [weak self, dependencies] in
            for await keys in dependencies.favorites.observeFavoriteKeys() {
                guard let self, !Task.isCancelled else { return }
                self.favoriteKeys = keys
            }
        }
    }
}
