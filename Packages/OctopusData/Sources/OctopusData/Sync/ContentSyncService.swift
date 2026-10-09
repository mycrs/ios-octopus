import Foundation
import CryptoKit
import OctopusCore
import OctopusDomain

/// Kaynağı yerel veritabanıyla eşitler.
///
/// Akış: kimlik doğrula → canlı/film/dizi kataloglarını bağımsız getir → yaz.
/// Her aşama `SyncStage` olarak yayınlanır; onboarding ekranı bunu gösterir.
///
/// ## Kısmi başarı kabul edilir
/// Hesap yalnızca canlı, film veya dizi taşıyabilir. En az bir katalog ucu
/// başarılıysa diğer uçların hatası çalışan içeriği engellemez. Başarısız
/// bir uç yerel kataloğunu silmez; üçü de başarısızsa sonuç hata olur.
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
    private struct ActiveSync {
        let id: UUID
        let task: Task<Void, Error>
    }
    private var activeSyncs: [String: ActiveSync] = [:]
    private var activeEPGSyncs: [String: ActiveSync] = [:]

    public init(
        playlists: PlaylistRepository,
        providerFactory: ContentProviderFactory,
        database: AppDatabase,
        httpClient: HTTPClient? = nil,
        store: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { Date() }
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
        try Task.checkCancellation()
        // Kullanıcı iki kez "yenile" derse iki tam senkronizasyon başlamasın.
        if let running = activeSyncs[playlistID.value] {
            try await running.task.value
            try Task.checkCancellation()
            return
        }

        let task = Task<Void, Error> { [weak self] in
            guard let self else { return }
            try await self.performSync(playlistID: playlistID)
        }
        let taskID = UUID()
        activeSyncs[playlistID.value] = ActiveSync(id: taskID, task: task)

        defer {
            if activeSyncs[playlistID.value]?.id == taskID { activeSyncs[playlistID.value] = nil }
        }

        do {
            try await task.value
            try Task.checkCancellation()
        } catch is CancellationError {
            if activeSyncs[playlistID.value]?.id == taskID { publish(.idle, for: playlistID) }
            throw CancellationError()
        } catch {
            let appError = AppError.wrap(error)
            if activeSyncs[playlistID.value]?.id == taskID { publish(.failed(appError), for: playlistID) }
            throw appError
        }
    }

    private func performSync(playlistID: Playlist.ID) async throws {
        try Task.checkCancellation()
        guard let playlist = try await playlists.playlist(id: playlistID) else {
            throw AppError.notFound
        }

        let provider = try await providerFactory.makeProvider(for: playlist)
        // Aynı sağlayıcı oturum boyunca korunur. Elle yenilemede M3U'nun
        // eski belleği kullanılmasın; aşamalar yine tek indirmeyi paylaşır.
        await provider.invalidateCache()
        var contentCounts = SyncContentCounts.empty
        var successfulCatalogs = 0
        var firstCatalogError: AppError?

        publish(.authenticating, for: playlistID)
        let account: ProviderAccount
        do {
            // Eski bitiş tarihi doğrulamayı engellemez: yenilenmiş hesap açılabilmeli.
            account = try await provider.authenticate()
        } catch let error as AppError {
            if case .subscriptionUnavailable(let block) = error {
                // Yazım hatası doğrulanmış erişim reddini genel ağ hatasına çevirmesin.
                try? await playlists.updateSubscription(
                    id: playlistID, status: block.status, expiresAt: block.expiresAt
                )
            }
            throw error
        }
        try Task.checkCancellation()

        let block = account.subscriptionBlock(at: now())
        if let block {
            // A provider may return a denied account instead of throwing.
            // Preserve that denial even when its local metadata cannot be saved.
            try? await playlists.updateSubscription(
                id: playlistID, status: block.status, expiresAt: block.expiresAt
            )
            throw AppError.subscriptionUnavailable(block)
        }
        if playlist.expiresAt != account.expiresAt || playlist.subscriptionStatus != account.subscriptionStatus {
            try await playlists.updateSubscription(
                id: playlistID, status: account.subscriptionStatus, expiresAt: account.expiresAt
            )
        }

        // Kataloglar bağımsızdır: canlı ucu olmayan bir film hesabı da çalışır.
        let live = try await fetchCatalog(label: "canlı") {
            self.publish(.fetchingCategories, for: playlistID)
            let categories = try await provider.fetchCategories(kind: .live)
            try Task.checkCancellation()
            self.publish(.fetchingChannels(done: 0, total: nil), for: playlistID)
            let items = try await provider.fetchChannels(categoryID: nil)
            return FetchedCatalog(categories: categories, items: items)
        }
        switch live {
        case .success(let catalog):
            try Task.checkCancellation()
            publish(.persisting, for: playlistID)
            // Yazım hatası bir eksik paket değildir; başarı diye yutulmaz.
            try await writer.replaceLiveCatalog(
                playlistID: playlistID,
                categories: catalog.categories,
                channels: AdultContentDetector.markAdultContent(
                    catalog.items, categories: catalog.categories
                )
            )
            successfulCatalogs += 1
            contentCounts.channels = catalog.items.count
            publish(.fetchingChannels(done: catalog.items.count, total: catalog.items.count), for: playlistID)
        case .failure(let error):
            firstCatalogError = error
        }

        let movies = try await fetchCatalog(label: "film") {
            self.publish(.fetchingMovies(done: 0, total: nil), for: playlistID)
            let categories = try await provider.fetchCategories(kind: .movie)
            let items = try await provider.fetchMovies(categoryID: nil)
            return FetchedCatalog(categories: categories, items: items)
        }
        switch movies {
        case .success(let catalog):
            try Task.checkCancellation()
            try await self.writer.replaceMovieCatalog(
                playlistID: playlistID,
                categories: catalog.categories,
                movies: AdultContentDetector.markAdultContent(catalog.items, categories: catalog.categories)
            )
            successfulCatalogs += 1
            contentCounts.movies = catalog.items.count
            publish(.fetchingMovies(done: catalog.items.count, total: catalog.items.count), for: playlistID)
        case .failure(let error):
            firstCatalogError = firstCatalogError ?? error
        }

        let series = try await fetchCatalog(label: "dizi") {
            self.publish(.fetchingSeries(done: 0, total: nil), for: playlistID)
            let categories = try await provider.fetchCategories(kind: .series)
            let items = try await provider.fetchSeries(categoryID: nil)
            return FetchedCatalog(categories: categories, items: items)
        }
        switch series {
        case .success(let catalog):
            try Task.checkCancellation()
            try await self.writer.replaceSeriesCatalog(
                playlistID: playlistID,
                categories: catalog.categories,
                series: AdultContentDetector.markAdultContent(catalog.items, categories: catalog.categories)
            )
            successfulCatalogs += 1
            contentCounts.series = catalog.items.count
            publish(.fetchingSeries(done: catalog.items.count, total: catalog.items.count), for: playlistID)
        case .failure(let error):
            firstCatalogError = firstCatalogError ?? error
        }

        guard successfulCatalogs > 0 else {
            throw firstCatalogError ?? AppError.invalidResponse(reason: "Kaynak katalogları alınamadı")
        }

        // ── Yayın akışı: isteğe bağlı ───────────────────────────────
        // Referans dersi: rehber yalnızca manuel butondan çekildiği için
        // her yerde "Bilgi yok" yazıyordu. Artık senkronizasyonun parçası,
        // ama başarısızlığı katalogu geçersiz kılmıyor.
        do {
            try await syncEPG(playlistID: playlistID)
        } catch is CancellationError {
            throw CancellationError()
        } catch AppError.storage(let reason) {
            // Rehber ağı isteğe bağlıdır; yerel kayıt arızası başarı sayılmaz.
            throw AppError.storage(reason: reason)
        } catch {
            Log.sync.info("EPG alınamadı, katalog kullanılmaya devam ediyor")
        }

        let finishedAt = now()
        try Task.checkCancellation()
        try await writer.markSynced(playlistID: playlistID, at: finishedAt)
        publish(.finished(at: finishedAt, counts: contentCounts), for: playlistID)
    }

    private struct FetchedCatalog<Item: Sendable>: Sendable {
        let categories: [MediaCategory]
        let items: [Item]
    }

    /// Yalnızca indirme hatası kısmi başarıya dönüşür. Kayıt ayrı yapılır;
    /// başarısız indirmede eski yerel veriye hiç dokunulmaz.
    private func fetchCatalog<Value: Sendable>(
        label: String,
        work: () async throws -> Value
    ) async throws -> Result<Value, AppError> {
        try Task.checkCancellation()
        do {
            let value = try await work()
            try Task.checkCancellation()
            return .success(value)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Hesapta bu paket yoksa normal bir durumdur.
            Log.sync.info("\(label) kataloğu alınamadı, yerel kayıt korunuyor")
            return .failure(AppError.wrap(error))
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
        try Task.checkCancellation()
        if let running = activeEPGSyncs[playlistID.value] {
            try await running.task.value
            try Task.checkCancellation()
            return
        }
        let task = Task { try await self.performSyncEPG(playlistID: playlistID) }
        let taskID = UUID()
        activeEPGSyncs[playlistID.value] = ActiveSync(id: taskID, task: task)
        defer {
            if activeEPGSyncs[playlistID.value]?.id == taskID { activeEPGSyncs[playlistID.value] = nil }
        }
        try await task.value
        try Task.checkCancellation()
    }

    public func cancel(playlistID: Playlist.ID) async {
        activeSyncs.removeValue(forKey: playlistID.value)?.task.cancel()
        if let epg = activeEPGSyncs.removeValue(forKey: playlistID.value) {
            epg.task.cancel()
            // Bilinçli iptal ağ hatası değildir; sonraki kaynak açılışını
            // altı saat boyunca kısıtlamamalı.
            store.removeObject(forKey: Self.epgAttemptKey(playlistID))
        }
    }

    private func performSyncEPG(playlistID: Playlist.ID) async throws {
        try Task.checkCancellation()
        guard let playlist = try await playlists.playlist(id: playlistID) else {
            throw AppError.notFound
        }
        let provider = try await providerFactory.makeProvider(for: playlist)
        try Task.checkCancellation()

        if let local = provider.localEPGPrograms(at: now()) {
            try writer.appendEPGChunk(local, playlistID: playlistID)
            try? writer.purgeEPG(before: now().addingTimeInterval(-6 * 3_600))
            return
        }

        // Kaynak rehber sunmuyor olabilir; bu bir hata değil.
        guard let epgURL = provider.epgSourceURL else { return }
        let fingerprint = Self.epgFingerprint(epgURL)
        guard shouldRefreshEPG(playlistID: playlistID, fingerprint: fingerprint) else { return }

        publish(.fetchingEPG, for: playlistID)
        markEPGAttempt(playlistID: playlistID, fingerprint: fingerprint)

        let data = try await httpClient.get(epgURL, headers: provider.streamHeaders)
        try Task.checkCancellation()

        // Çözümleme ve yazma senkron; ana iş parçacığını meşgul etmemek için
        // ayrı bir görevde çalıştırılır.
        let writer = self.writer
        let parsing = Task.detached(priority: .utility) {
            var latestEnd: Date?
            let count = try XMLTVParser.parse(data: data, chunkSize: XMLTVParser.defaultChunkSize) { chunk in
                try Task.checkCancellation()
                try writer.appendEPGChunk(chunk, playlistID: playlistID)
                if let chunkEnd = chunk.map(\.endDate).max() {
                    latestEnd = latestEnd.map { max($0, chunkEnd) } ?? chunkEnd
                }
            }
            return ParsedGuide(count: count, latestEnd: latestEnd)
        }
        let parsed = try await withTaskCancellationHandler {
            try await parsing.value
        } onCancel: {
            parsing.cancel()
        }
        try Task.checkCancellation()
        store.set(fingerprint, forKey: Self.epgSuccessFingerprintKey(playlistID))
        if let latestEnd = parsed.latestEnd {
            store.set(latestEnd, forKey: Self.epgCoverageKey(playlistID))
        } else {
            store.removeObject(forKey: Self.epgCoverageKey(playlistID))
        }

        // Geçmiş programlar birikmesin. Biraz geriye pay bırakılır:
        // kullanıcı "az önce ne oynadı" bilgisini görebilmeli.
        try? writer.purgeEPG(before: now().addingTimeInterval(-6 * 3_600))

        Log.sync.info("EPG güncellendi: \(parsed.count) program")
    }

    // MARK: - EPG kapıları

    private struct ParsedGuide: Sendable {
        let count: Int
        let latestEnd: Date?
    }

    private func shouldRefreshEPG(playlistID: Playlist.ID, fingerprint: String) -> Bool {
        // Kapsam: rehber en az 2 saat ileriyi kapsıyorsa yeniden indirme.
        // Yalnızca TAM çözümlenmiş aynı rehberin kapsamı geçerlidir; bozuk
        // XML'in yazılmış ilk parçası sonraki denemeleri bastıramaz.
        if store.string(forKey: Self.epgSuccessFingerprintKey(playlistID)) == fingerprint,
           let completedEnd = store.object(forKey: Self.epgCoverageKey(playlistID)) as? Date,
           completedEnd > now().addingTimeInterval(2 * 3_600),
           let latest = try? writer.latestEPGEnd(playlistID: playlistID),
           latest > now().addingTimeInterval(2 * 3_600) {
            Log.sync.debug("EPG hâlâ güncel, indirme atlandı")
            return false
        }

        // Kısıtlama: başarısız denemeler de sayılır, yoksa kopuk sunucuda
        // her açılışta yüzlerce megabayt denemesi yapılır.
        let key = Self.epgAttemptKey(playlistID)
        if store.string(forKey: Self.epgAttemptFingerprintKey(playlistID)) == fingerprint,
           let last = store.object(forKey: key) as? Date,
           now().timeIntervalSince(last) < 6 * 3_600 {
            Log.sync.debug("EPG denemesi kısıtlama nedeniyle atlandı")
            return false
        }

        return true
    }

    private func markEPGAttempt(playlistID: Playlist.ID, fingerprint: String) {
        store.set(now(), forKey: Self.epgAttemptKey(playlistID))
        store.set(fingerprint, forKey: Self.epgAttemptFingerprintKey(playlistID))
    }

    private static func epgAttemptKey(_ playlistID: Playlist.ID) -> String {
        "epg.lastAttempt.\(playlistID.value)"
    }

    private static func epgAttemptFingerprintKey(_ playlistID: Playlist.ID) -> String {
        "epg.attemptFingerprint.\(playlistID.value)"
    }

    private static func epgSuccessFingerprintKey(_ playlistID: Playlist.ID) -> String {
        "epg.successFingerprint.\(playlistID.value)"
    }

    private static func epgCoverageKey(_ playlistID: Playlist.ID) -> String {
        "epg.completedCoverage.\(playlistID.value)"
    }

    private static func epgFingerprint(_ url: URL) -> String {
        // URL hesap bilgisi taşıyabilir; UserDefaults'a ham adres yazılmaz.
        SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
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
