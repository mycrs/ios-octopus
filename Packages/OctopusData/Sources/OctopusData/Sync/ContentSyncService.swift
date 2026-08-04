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

    /// Aynı kaynağa birden çok abone olabilir (onboarding + ayarlar).
    private var observers: [String: [UUID: AsyncStream<SyncStage>.Continuation]] = [:]
    private var lastStage: [String: SyncStage] = [:]
    /// Devam eden senkronizasyon — ikinci çağrı aynı işi beklesin.
    private var activeSyncs: [String: Task<Void, Error>] = [:]

    public init(
        playlists: PlaylistRepository,
        providerFactory: ContentProviderFactory,
        database: AppDatabase
    ) {
        self.playlists = playlists
        self.providerFactory = providerFactory
        self.writer = CatalogWriter(database: database)
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

        publish(.authenticating, for: playlistID)
        _ = try await provider.authenticate()
        try Task.checkCancellation()

        // ── Canlı yayın: zorunlu ────────────────────────────────────
        publish(.fetchingCategories, for: playlistID)
        let liveCategories = try await provider.fetchCategories(kind: .live)
        try Task.checkCancellation()

        publish(.fetchingChannels(done: 0, total: nil), for: playlistID)
        let channels = try await provider.fetchChannels(categoryID: nil)
        try Task.checkCancellation()

        publish(.persisting, for: playlistID)
        try await writer.replaceLiveCatalog(
            playlistID: playlistID,
            categories: liveCategories,
            channels: channels
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
                movies: movies
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
                series: series
            )
        }

        let finishedAt = Date()
        try await writer.markSynced(playlistID: playlistID, at: finishedAt)
        publish(.finished(at: finishedAt), for: playlistID)
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

    public func syncEPG(playlistID: Playlist.ID) async throws {
        // Faz 7: xmltv.php akış halinde indirilip parça parça yazılacak.
        // XMLTVParser ve CatalogWriter.appendEPGChunk hazır.
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
