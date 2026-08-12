import Foundation
import OctopusCore
import OctopusDomain

/// Kaynağı yerel veritabanıyla eşitler.
///
/// Akış: kimlik doğrula → kategoriler → kanallar → filmler → diziler → yaz.
/// Her aşama `SyncStage` olarak yayınlanır; onboarding ekranı bunu gösterir.
///
/// ## Kısmi başarı kabul edilir
/// Xtream hesaplarının çoğunda film veya dizi paketi yoktur; bu uçlar hata
/// döner. Canlı yayın alındıysa senkronizasyon **başarılı sayılır** —
/// aksi halde kullanıcı çalışan bir hesapta "senkronizasyon başarısız"
/// görürdü.
public actor ContentSyncService: ContentSyncing {

    private let playlists: PlaylistRepository
    private let providerFactory: ContentProviderFactory
    private let writer: CatalogWriter
    private let httpClient: HTTPClient
    private let store: UserDefaults
    private let now: @Sendable () -> Date

    /// Aynı kaynağa birden çok abone olabilir (onboarding + ayarlar).
    private var observers: [String: [UUID: AsyncStream<SyncStage>.Continuation]] = [:]
    private var lastStage: [String: SyncStage] = [:]
    /// Devam eden senkronizasyon — ikinci çağrı aynı işi beklesin.
    private var activeSyncs: [String: Task<Void, Error>] = [:]

    public init(
        playlists: PlaylistRepository,
        providerFactory: ContentProviderFactory,
        database: AppDatabase,
        httpClient: HTTPClient? = nil,
        store: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.playlists = playlists
        self.providerFactory = providerFactory
        self.writer = CatalogWriter(database: database)
        self.httpClient = httpClient ?? URLSessionHTTPClient()
        self.store = store
        self.now = now
    }

    // MARK: - Senkronizasyon

    public func sync(playlistID: Playlist.ID) async throws {
        // Kullanıcı iki kez "yenile" derse iki tam senkronizasyon başlamasın.
        if let running = activeSyncs[playlistID.value] {
            return try await running.value
        }

        let task = Task<Void, Error> { [weak self] in
            guard let self else { return }
            try await self.performSync(playlistID: playlistID)
        }
        activeSyncs[playlistID.value] = task

        defer { activeSyncs[playlistID.value] = nil }

        do {
            try await task.value
        } catch is CancellationError {
            publish(.idle, for: playlistID)
            throw CancellationError()
        } catch {
            let appError = AppError.wrap(error)
            publish(.failed(appError), for: playlistID)
            throw appError
        }
    }

    private func performSync(playlistID: Playlist.ID) async throws {
        guard let playlist = try await playlists.playlist(id: playlistID) else {
            throw AppError.notFound
        }

        let provider = try await providerFactory.makeProvider(for: playlist)
        var contentCounts = SyncContentCounts.empty

        publish(.authenticating, for: playlistID)
        let account = try await provider.authenticate()
        try Task.checkCancellation()

        // ⚠️ Abonelik bitişi **atılmıyor** artık: bu çağrı zaten yapılıyordu
        // ve dönen bilgi kullanıcı için en değerli veri ("kaç günüm kaldı").
        // Kayıt başarısız olursa senkronizasyon durmaz — katalog, abonelik
        // rozetinden önemlidir.
        if playlist.expiresAt != account.expiresAt {
            var updated = playlist
            updated.expiresAt = account.expiresAt
            try? await playlists.update(updated)
        }

        // ── Canlı yayın: zorunlu ────────────────────────────────────
        publish(.fetchingCategories, for: playlistID)
        let liveCategories = try await provider.fetchCategories(kind: .live)
        try Task.checkCancellation()

        publish(.fetchingChannels(done: 0, total: nil), for: playlistID)
        let channels = try await provider.fetchChannels(categoryID: nil)
        try Task.checkCancellation()
        contentCounts.channels = channels.count
        publish(
            .fetchingChannels(done: channels.count, total: channels.count),
            for: playlistID
        )

        publish(.persisting, for: playlistID)
        try await writer.replaceLiveCatalog(
            playlistID: playlistID,
            categories: liveCategories,
            // ⚠️ Yetişkin bayrağı burada tamamlanır: sağlayıcıların çoğu
            // `is_adult` alanını doldurmuyor, M3U'da böyle bir alan hiç yok.
            // Kategori adı ile içerik ancak bu noktada bir arada.
            channels: AdultContentDetector.markAdultContent(
                channels,
                categories: liveCategories
            )
        )

        // ── Film ve dizi: isteğe bağlı ──────────────────────────────
        // Bu paketler her hesapta bulunmaz; hata senkronizasyonu düşürmemeli.
        try await syncOptional(
            label: "film",
            playlistID: playlistID,
            stage: { .fetchingMovies(done: 0, total: nil) }
        ) {
            let categories = try await provider.fetchCategories(kind: .movie)
            let movies = try await provider.fetchMovies(categoryID: nil)
            try await self.writer.replaceMovieCatalog(
                playlistID: playlistID,
                categories: categories,
                movies: AdultContentDetector.markAdultContent(movies, categories: categories)
            )
            contentCounts.movies = movies.count
            self.publish(
                .fetchingMovies(done: movies.count, total: movies.count),
                for: playlistID
            )
        }

        try await syncOptional(
            label: "dizi",
            playlistID: playlistID,
            stage: { .fetchingSeries(done: 0, total: nil) }
        ) {
            let categories = try await provider.fetchCategories(kind: .series)
            let series = try await provider.fetchSeries(categoryID: nil)
            try await self.writer.replaceSeriesCatalog(
                playlistID: playlistID,
                categories: categories,
                series: AdultContentDetector.markAdultContent(series, categories: categories)
            )
            contentCounts.series = series.count
            self.publish(
                .fetchingSeries(done: series.count, total: series.count),
                for: playlistID
            )
        }

        // ── Yayın akışı: isteğe bağlı ───────────────────────────────
        // Referans dersi: rehber yalnızca manuel butondan çekildiği için
        // her yerde "Bilgi yok" yazıyordu. Artık senkronizasyonun parçası,
        // ama başarısızlığı katalogu geçersiz kılmıyor.
        do {
            try await syncEPG(playlistID: playlistID)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Log.sync.info("EPG alınamadı, atlanıyor: \(String(describing: error))")
        }

        let finishedAt = now()
        try await writer.markSynced(playlistID: playlistID, at: finishedAt)
        publish(.finished(at: finishedAt, counts: contentCounts), for: playlistID)
    }

    /// İsteğe bağlı bölüm: başarısızlık loglanır ama senkronizasyon sürer.
    private func syncOptional(
        label: String,
        playlistID: Playlist.ID,
        stage: () -> SyncStage,
        work: () async throws -> Void
    ) async throws {
        try Task.checkCancellation()
        publish(stage(), for: playlistID)
        do {
            try await work()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Hesapta bu paket yoksa normal bir durumdur.
            Log.sync.info("\(label) kataloğu alınamadı, atlanıyor: \(String(describing: error))")
        }
    }

    /// Yayın akışını (EPG) tazeler.
    ///
    /// ## Neden bu kadar temkinli?
    /// XMLTV dosyaları 14.000 kanallı hesapta yüzlerce megabayt olabiliyor.
    /// Referans projede rehber yalnızca Ayarlar'daki manuel butondan
    /// çekiliyordu ve sonuçta her yerde "Bilgi yok" yazıyordu; otomatik
    /// hâle getirilince de her açılışta indirme sorunu doğdu.
    ///
    /// İki kapı var:
    /// 1. **Kapsam**: rehber hâlâ ileriyi kapsıyorsa indirme yapılmaz
    /// 2. **Kısıtlama**: kaynak başına en fazla 6 saatte bir denenir
    public func syncEPG(playlistID: Playlist.ID) async throws {
        guard let playlist = try await playlists.playlist(id: playlistID) else {
            throw AppError.notFound
        }
        let provider = try await providerFactory.makeProvider(for: playlist)

        // Kaynak rehber sunmuyor olabilir; bu bir hata değil.
        guard let epgURL = provider.epgSourceURL else { return }
        guard shouldRefreshEPG(playlistID: playlistID) else { return }

        publish(.fetchingEPG, for: playlistID)
        markEPGAttempt(playlistID: playlistID)

        let data = try await httpClient.get(epgURL, headers: provider.streamHeaders)
        try Task.checkCancellation()

        // Çözümleme ve yazma senkron; ana iş parçacığını meşgul etmemek için
        // ayrı bir görevde çalıştırılır.
        let writer = self.writer
        let total = try await Task.detached(priority: .utility) {
            try XMLTVParser.parse(data: data, chunkSize: XMLTVParser.defaultChunkSize) { chunk in
                try writer.appendEPGChunk(chunk)
            }
        }.value

        // Geçmiş programlar birikmesin. Biraz geriye pay bırakılır:
        // kullanıcı "az önce ne oynadı" bilgisini görebilmeli.
        try? writer.purgeEPG(before: now().addingTimeInterval(-6 * 3_600))

        Log.sync.info("EPG güncellendi: \(total) program")
    }

    // MARK: - EPG kapıları

    private func shouldRefreshEPG(playlistID: Playlist.ID) -> Bool {
        // Kapsam: rehber en az 2 saat ileriyi kapsıyorsa yeniden indirme.
        if let latest = try? writer.latestEPGEnd(),
           latest > now().addingTimeInterval(2 * 3_600) {
            Log.sync.debug("EPG hâlâ güncel, indirme atlandı")
            return false
        }

        // Kısıtlama: başarısız denemeler de sayılır, yoksa kopuk sunucuda
        // her açılışta yüzlerce megabayt denemesi yapılır.
        let key = Self.epgAttemptKey(playlistID)
        if let last = store.object(forKey: key) as? Date,
           now().timeIntervalSince(last) < 6 * 3_600 {
            Log.sync.debug("EPG denemesi kısıtlama nedeniyle atlandı")
            return false
        }

        return true
    }

    private func markEPGAttempt(playlistID: Playlist.ID) {
        store.set(now(), forKey: Self.epgAttemptKey(playlistID))
    }

    private static func epgAttemptKey(_ playlistID: Playlist.ID) -> String {
        "epg.lastAttempt.\(playlistID.value)"
    }

    // MARK: - İlerleme yayını

    public nonisolated func observeProgress(playlistID: Playlist.ID) -> AsyncStream<SyncStage> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.register(continuation, id: id, playlistID: playlistID) }
            continuation.onTermination = { _ in
                Task { await self.unregister(id: id, playlistID: playlistID) }
            }
        }
    }

    private func register(
        _ continuation: AsyncStream<SyncStage>.Continuation,
        id: UUID,
        playlistID: Playlist.ID
    ) {
        observers[playlistID.value, default: [:]][id] = continuation
        // Yeni abone mevcut durumu hemen görsün — ekran boş açılmasın.
        continuation.yield(lastStage[playlistID.value] ?? .idle)
    }

    private func unregister(id: UUID, playlistID: Playlist.ID) {
        observers[playlistID.value]?[id] = nil
    }

    private func publish(_ stage: SyncStage, for playlistID: Playlist.ID) {
        lastStage[playlistID.value] = stage
        for continuation in observers[playlistID.value]?.values ?? [:].values {
            continuation.yield(stage)
        }
    }
}
