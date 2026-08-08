import Foundation

/// Akış konteyner/protokol türü. **Motor seçimi buna göre yapılır.**
public enum StreamFormat: String, Codable, Hashable, Sendable, CaseIterable {
    case hls        // .m3u8  → AVPlayer
    case mp4        // .mp4/.mov → AVPlayer
    case mpegTS     // .ts    → VLC
    case mkv        // .mkv   → VLC
    case avi        // .avi   → VLC
    case rtsp       // rtsp://→ VLC
    case rtmp       // rtmp://→ VLC
    case unknown    // önce AVPlayer denenir, hata olursa VLC'ye düşülür

    /// URL'den format çıkarımı. Saf fonksiyon — ağ isteği yapmaz.
    public static func detect(from url: URL) -> StreamFormat {
        switch url.scheme?.lowercased() {
        case "rtsp": return .rtsp
        case "rtmp", "rtmps": return .rtmp
        default: break
        }

        switch url.pathExtension.lowercased() {
        case "m3u8": return .hls
        case "ts", "mpegts": return .mpegTS
        case "mp4", "mov", "m4v": return .mp4
        case "mkv": return .mkv
        case "avi": return .avi
        default: return .unknown
        }
    }

    /// AVFoundation bu formatı yerel olarak açabilir mi?
    public var isNativelySupported: Bool {
        switch self {
        case .hls, .mp4: return true
        case .mpegTS, .mkv, .avi, .rtsp, .rtmp: return false
        case .unknown: return true   // önce dene, başarısız olursa fallback
        }
    }
}

/// Oynatıcıya verilen tek birim. UI bunu üretir, motor bunu tüketir.
public struct PlaybackItem: Hashable, Sendable {

    /// İçeriğin kökeni — izleme geçmişi ve "kaldığın yerden devam" bunu kullanır.
    public enum Source: Hashable, Sendable {
        case liveChannel(Channel.ID)
        case movie(Movie.ID)
        case episode(Episode.ID)
    }

    public let source: Source
    public let url: URL
    public let format: StreamFormat

    public let title: String
    public let subtitle: String?
    public let artworkURL: URL?

    /// Canlı yayın mı? (Seek çubuğu, "CANLI" rozeti, arka plan davranışı buna bakar.)
    public let isLive: Bool

    /// Kaldığı yerden devam saniyesi. Canlıda `nil`.
    public let resumeAt: TimeInterval?

    /// İstek başlıkları.
    ///
    /// ⚠️ IPTV'de kritik: birçok panel `User-Agent` kontrol eder ve
    /// beklenmeyen değerde 403 döner. Motorlar bunu isteğe eklemek zorundadır.
    public let headers: [String: String]

    public init(
        source: Source,
        url: URL,
        format: StreamFormat? = nil,
        title: String,
        subtitle: String? = nil,
        artworkURL: URL? = nil,
        isLive: Bool,
        resumeAt: TimeInterval? = nil,
        headers: [String: String] = [:]
    ) {
        self.source = source
        self.url = url
        self.format = format ?? StreamFormat.detect(from: url)
        self.title = title
        self.subtitle = subtitle
        self.artworkURL = artworkURL
        self.isLive = isLive
        self.resumeAt = isLive ? nil : resumeAt
        self.headers = headers
    }
}

extension PlaybackItem {

    /// Aynı içeriğin, kaldığı yerden başlayan kopyası.
    ///
    /// Akış adresini üreten katman (`StreamResolving`) izleme geçmişini
    /// bilmez — bilmemeli de. Devam konumu oynatma başlarken eklenir.
    /// Canlı yayında `init` zaten `nil`'e çeker.
    public func resuming(at seconds: TimeInterval?) -> PlaybackItem {
        PlaybackItem(
            source: source,
            url: url,
            format: format,
            title: title,
            subtitle: subtitle,
            artworkURL: artworkURL,
            isLive: isLive,
            resumeAt: seconds,
            headers: headers
        )
    }
}

/// Bir içeriğin ne kadarının izlendiği.
public struct PlaybackProgress: Hashable, Codable, Sendable {
    public let itemKey: String          // Source'un kararlı string karşılığı
    public var positionSeconds: Double
    public var durationSeconds: Double
    public var updatedAt: Date

    public init(
        itemKey: String,
        positionSeconds: Double,
        durationSeconds: Double,
        updatedAt: Date
    ) {
        self.itemKey = itemKey
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.updatedAt = updatedAt
    }

    public var fraction: Double {
        guard durationSeconds > 0 else { return 0 }
        return min(max(positionSeconds / durationSeconds, 0), 1)
    }

    /// %95'i geçtiyse izlenmiş sayılır — listede "devam et" olarak gösterilmez.
    public var isFinished: Bool { fraction >= 0.95 }
}

extension PlaybackItem.Source {

    /// Veritabanı anahtarı olarak kullanılabilir kararlı temsil.
    public var storageKey: String {
        switch self {
        case .liveChannel(let id): return "live:\(id.value)"
        case .movie(let id): return "movie:\(id.value)"
        case .episode(let id): return "episode:\(id.value)"
        }
    }

    /// Anahtarı geri çözer.
    ///
    /// İzleme ilerlemesi kayıtları yalnızca anahtar taşır; "izlemeye devam et"
    /// rafı bu anahtardan hangi içeriğe ait olduğunu bulur.
    ///
    /// - Note: Kimlik değerinin kendisi `:` içerebilir (M3U'da akış adresi
    ///   kimliktir), bu yüzden yalnızca **ilk** iki nokta üst üste ayraçtır.
    public init?(storageKey: String) {
        guard let separatorIndex = storageKey.firstIndex(of: ":") else { return nil }

        let prefix = String(storageKey[storageKey.startIndex..<separatorIndex])
        let rawID = String(storageKey[storageKey.index(after: separatorIndex)...])
        guard !rawID.isEmpty else { return nil }

        switch prefix {
        case "live": self = .liveChannel(Channel.ID(rawID))
        case "movie": self = .movie(Movie.ID(rawID))
        case "episode": self = .episode(Episode.ID(rawID))
        default: return nil
        }
    }
}
