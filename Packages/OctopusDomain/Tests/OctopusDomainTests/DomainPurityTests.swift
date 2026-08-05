import XCTest
@testable import OctopusDomain

/// Domain saf Swift olduğu için testleri simülatörsüz, milisaniyeler içinde koşar.
/// Bu hız kasıtlıdır: iş kuralları anında doğrulanabilmelidir.
final class DomainPurityTests: XCTestCase {

    // MARK: - Format çıkarımı (motor seçiminin temeli)

    func test_streamFormat_detectsFromExtension() {
        XCTAssertEqual(StreamFormat.detect(from: URL(string: "http://a.tv/live/1.m3u8")!), .hls)
        XCTAssertEqual(StreamFormat.detect(from: URL(string: "http://a.tv/live/1.ts")!), .mpegTS)
        XCTAssertEqual(StreamFormat.detect(from: URL(string: "http://a.tv/movie/1.mkv")!), .mkv)
        XCTAssertEqual(StreamFormat.detect(from: URL(string: "rtsp://a.tv/stream")!), .rtsp)
        XCTAssertEqual(StreamFormat.detect(from: URL(string: "http://a.tv/live/1")!), .unknown)
    }

    func test_nativeSupport_routesToCorrectEngine() {
        XCTAssertTrue(StreamFormat.hls.isNativelySupported)
        XCTAssertTrue(StreamFormat.mp4.isNativelySupported)
        XCTAssertFalse(StreamFormat.mpegTS.isNativelySupported)
        XCTAssertFalse(StreamFormat.rtsp.isNativelySupported)
        // Bilinmeyende önce AVPlayer denenir, hata olursa VLC'ye düşülür.
        XCTAssertTrue(StreamFormat.unknown.isNativelySupported)
    }

    // MARK: - Canlı yayında devam etme noktası olmamalı

    func test_playbackItem_liveStreamDiscardsResumePosition() {
        let item = PlaybackItem(
            source: .liveChannel("ch1"),
            url: URL(string: "http://a.tv/live/1.ts")!,
            title: "TRT 1",
            isLive: true,
            resumeAt: 120
        )
        XCTAssertNil(item.resumeAt, "Canlı yayın kaldığı yerden devam edemez")
        XCTAssertEqual(item.format, .mpegTS, "Format URL'den otomatik çıkarılmalı")
    }

    // MARK: - EPG zaman hesapları (Date() ÇAĞIRMADAN — saf)

    func test_epgProgram_progressIsClampedAndPure() {
        let start = Date(timeIntervalSince1970: 1_000)
        let program = EPGProgram(
            id: "p1",
            epgChannelID: "trt1",
            title: "Haber",
            startDate: start,
            endDate: start.addingTimeInterval(3_600)
        )

        XCTAssertEqual(program.progress(at: start), 0)
        XCTAssertEqual(program.progress(at: start.addingTimeInterval(1_800)), 0.5)
        XCTAssertEqual(program.progress(at: start.addingTimeInterval(9_999)), 1, "Üst sınıra sabitlenmeli")
        XCTAssertEqual(program.progress(at: start.addingTimeInterval(-500)), 0, "Alt sınıra sabitlenmeli")

        XCTAssertTrue(program.isOnAir(at: start.addingTimeInterval(10)))
        XCTAssertFalse(program.isOnAir(at: program.endDate), "Bitiş anı dahil değil")
    }

    // MARK: - İzleme ilerlemesi

    func test_playbackProgress_marksFinishedAfterThreshold() {
        func progress(_ position: Double) -> PlaybackProgress {
            PlaybackProgress(
                itemKey: "movie:1",
                positionSeconds: position,
                durationSeconds: 100,
                updatedAt: Date(timeIntervalSince1970: 0)
            )
        }
        XCTAssertFalse(progress(50).isFinished)
        XCTAssertFalse(progress(94).isFinished)
        XCTAssertTrue(progress(95).isFinished)
    }

    func test_playbackProgress_handlesZeroDuration() {
        let progress = PlaybackProgress(
            itemKey: "live:1",
            positionSeconds: 42,
            durationSeconds: 0,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(progress.fraction, 0, "Sıfıra bölme olmamalı")
    }

    // MARK: - Tip güvenliği

    func test_identifier_isTypeSafeAcrossEntities() {
        let channelID: Channel.ID = "42"
        let movieID: Movie.ID = "42"
        // Aynı ham değere sahip olsalar da farklı tiplerdir; aşağıdaki satır DERLENMEZ:
        //   XCTAssertEqual(channelID, movieID)
        XCTAssertEqual(channelID.value, movieID.value)
    }

    func test_playbackSource_storageKeysDoNotCollide() {
        let keys = Set([
            PlaybackItem.Source.liveChannel("1").storageKey,
            PlaybackItem.Source.movie("1").storageKey,
            PlaybackItem.Source.episode("1").storageKey
        ])
        XCTAssertEqual(keys.count, 3, "Farklı türler aynı anahtarı üretmemeli")
    }

    func test_playbackSource_roundTripsThroughStorageKey() {
        // "İzlemeye devam et" rafı yalnızca anahtardan içeriği bulur.
        let sources: [PlaybackItem.Source] = [
            .liveChannel("p1#live#1"),
            .movie("p1#vod#9"),
            .episode("p1#series#77#e#101")
        ]

        for source in sources {
            XCTAssertEqual(
                PlaybackItem.Source(storageKey: source.storageKey),
                source,
                "\(source) gidiş-dönüşte bozuldu"
            )
        }
    }

    func test_playbackSource_keyWithColonInIdentifier() {
        // M3U kaynaklarında akış ADRESİ kimliktir ve iki nokta içerir:
        // yalnızca İLK iki nokta ayraç sayılmalı.
        let source = PlaybackItem.Source.liveChannel("p1#live#http://sunucu.example.com/1.ts")
        let restored = PlaybackItem.Source(storageKey: source.storageKey)
        XCTAssertEqual(restored, source)
    }

    func test_playbackSource_rejectsMalformedKeys() {
        XCTAssertNil(PlaybackItem.Source(storageKey: ""))
        XCTAssertNil(PlaybackItem.Source(storageKey: "onceksiz"))
        XCTAssertNil(PlaybackItem.Source(storageKey: "live:"), "Boş kimlik kabul edilmemeli")
        XCTAssertNil(PlaybackItem.Source(storageKey: "bilinmeyen:123"))
    }

    // MARK: - Hata sınıflandırması

    func test_appError_retryPolicy() {
        XCTAssertTrue(AppError.network(reason: "x").isRetryable)
        XCTAssertTrue(AppError.connectionLimitReached.isRetryable)
        XCTAssertFalse(AppError.unauthorized.isRetryable)
        XCTAssertTrue(AppError.unauthorized.requiresReauthentication)
    }

    func test_appError_wrapPreservesExistingAppError() {
        let original = AppError.notFound
        XCTAssertEqual(AppError.wrap(original), original)
        XCTAssertEqual(
            AppError.wrap(URLError(.userAuthenticationRequired)),
            .unauthorized
        )
    }

    // MARK: - Senkronizasyon ilerlemesi

    func test_syncStage_fractionIsMonotonicAndBounded() {
        XCTAssertEqual(SyncStage.idle.fraction, 0)
        XCTAssertEqual(SyncStage.finished(at: Date()).fraction, 1)
        XCTAssertNil(SyncStage.fetchingChannels(done: 5, total: nil).fraction,
                     "Toplam bilinmiyorsa belirsiz ilerleme gösterilmeli")
        XCTAssertNil(SyncStage.failed(.notFound).fraction)

        let half = SyncStage.fetchingChannels(done: 50, total: 100).fraction
        XCTAssertEqual(half ?? 0, 0.30, accuracy: 0.001)
    }
}
