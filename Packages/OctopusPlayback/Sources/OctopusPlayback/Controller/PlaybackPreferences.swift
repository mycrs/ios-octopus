import Foundation
import Combine
import OctopusDomain

/// Kullanıcının oynatma tercihleri.
///
/// ⚠️ Buraya **yalnızca gerçekten bir davranışı değiştiren** ayar girer.
/// İşlevsiz bir anahtar, hiç olmayan anahtardan kötüdür: kullanıcı
/// denediğinde bir şey değişmeyince uygulamanın tamamına güveni sarsılır.
/// Her alanın karşılığı yorumda yazılı.
///
/// `UserDefaults`: tercihler cihaza ait, hesaba değil — panel değişse de
/// kullanıcının seçtiği tampon süresi onun telefonu için doğru kalır.
@MainActor
public final class PlaybackPreferences: ObservableObject {

    /// Canlı yayında ilk kareden önce doldurulacak tampon.
    ///
    /// Doğrudan **kanal geçiş hızıdır**: tampon ne kadar büyükse yayın o
    /// kadar geç açılır ama takılma o kadar az olur. Bağlantısı iyi olan
    /// kullanıcı "Hızlı"yı, dalgalı hatta olan "Kararlı"yı ister.
    public enum LiveBuffer: String, CaseIterable, Identifiable, Sendable {
        case fast
        case balanced
        case stable

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .fast: return "Hızlı"
            case .balanced: return "Dengeli"
            case .stable: return "Kararlı"
            }
        }

        public var detail: String {
            switch self {
            case .fast: return "En kısa açılış, dalgalı hatta takılabilir"
            case .balanced: return "Dengeli açılış ve akıcılık"
            case .stable: return "Önerilen — en az takılma, biraz geç açılır"
            }
        }

        /// VLC `network-caching` değeri ve AVPlayer tampon hedefi.
        public var milliseconds: Int {
            switch self {
            case .fast: return 700
            case .balanced: return 1500
            case .stable: return 3000
            }
        }

        public var seconds: TimeInterval { Double(milliseconds) / 1000 }
    }

    /// Görüntünün çerçeveye yerleşimi — oynatıcıdaki düğme bunu değiştirir
    /// ve seçim burada kalıcılaşır (her yayında yeniden seçmek gerekmesin).
    @Published public var videoFit: VideoFit {
        didSet { store.set(videoFit.rawValue, forKey: Keys.videoFit) }
    }

    /// Canlı tampon süresi. Motorlar `load()` sırasında okur.
    @Published public var liveBuffer: LiveBuffer {
        didSet { store.set(liveBuffer.rawValue, forKey: Keys.liveBuffer) }
    }

    /// Kopan canlı yayına sessizce yeniden bağlanılsın mı?
    ///
    /// Kapatıldığında `PlayerController` ilk kopmada hata gösterir.
    @Published public var autoReconnect: Bool {
        didSet { store.set(autoReconnect, forKey: Keys.autoReconnect) }
    }

    /// AVPlayer'ın desteklemediği ya da açamadığı akışlarda VLC kullanılsın mı?
    ///
    /// ⚠️ Kapatmak **UHD/HEVC kanalları ile MKV/TS filmleri kaybettirebilir**
    /// ama teşhis için değerlidir: sorunun VLC'de mi yoksa yayında mı olduğu
    /// ancak böyle ayrılır.
    @Published public var useFallbackEngine: Bool {
        didSet { store.set(useFallbackEngine, forKey: Keys.useFallbackEngine) }
    }

    private enum Keys {
        static let videoFit = "playback.videoFit"
        static let liveBuffer = "playback.liveBuffer"
        static let autoReconnect = "playback.autoReconnect"
        static let useFallbackEngine = "playback.useFallbackEngine"
        static let fallbackSources = "playback.fallbackSources"
    }

    /// Daha önce yedek motor gerektirmiş kaynakların kararlı anahtarları.
    ///
    /// ⚠️ Neden kalıcı? Bir kanalın codec'i (ör. HEVC) değişmez. Her
    /// açılışta önce AVPlayer'ı deneyip başarısız olmasını beklemek,
    /// kullanıcıyı **her seferinde** siyah ekranda tutuyordu. Bir kez
    /// öğrenildikten sonra o kanal doğrudan yedek motorla açılıyor ve
    /// bekleme tamamen ortadan kalkıyor.
    ///
    /// Küçük tutulur: yalnızca anahtarlar saklanıyor, sınır aşılırsa en
    /// eskiler düşer — liste sonsuza kadar büyüyemez.
    private var fallbackSources: [String] {
        get { store.stringArray(forKey: Keys.fallbackSources) ?? [] }
        set { store.set(newValue, forKey: Keys.fallbackSources) }
    }

    private static let fallbackMemoryLimit = 300

    /// Bu kaynak daha önce yedek motor gerektirdi mi?
    public func requiresFallbackEngine(for storageKey: String) -> Bool {
        fallbackSources.contains(storageKey)
    }

    /// Kaynağı "yedek motor gerekiyor" diye işaretler.
    public func rememberFallbackEngine(for storageKey: String) {
        var keys = fallbackSources
        guard !keys.contains(storageKey) else { return }
        keys.append(storageKey)
        if keys.count > Self.fallbackMemoryLimit {
            keys.removeFirst(keys.count - Self.fallbackMemoryLimit)
        }
        fallbackSources = keys
    }

    /// Kaynak artık yedeğe ihtiyaç duymuyorsa işareti kaldırır.
    ///
    /// Sağlayıcı kanalı yeniden kodladığında (HEVC → H.264) kullanıcının
    /// kalıcı olarak yedek motora mahkûm kalmaması için gerekli.
    public func forgetFallbackEngine(for storageKey: String) {
        let keys = fallbackSources
        guard keys.contains(storageKey) else { return }
        fallbackSources = keys.filter { $0 != storageKey }
    }

    private let store: UserDefaults

    public init(store: UserDefaults = .standard) {
        self.store = store

        let rawFit = store.string(forKey: Keys.videoFit) ?? VideoFit.fit.rawValue
        self.videoFit = VideoFit(rawValue: rawFit) ?? .fit

        // ⚠️ Varsayılan **Kararlı**: IPTV sunucuları dalgalı, takılan bir
        // yayın kullanıcıya "uygulama bozuk" hissi veriyor. Açılışın biraz
        // gecikmesi, izlerken donmaktan iyidir. Hızlı zaplama isteyen
        // kullanıcı Ayarlar'dan "Hızlı"ya alabilir.
        let rawBuffer = store.string(forKey: Keys.liveBuffer) ?? LiveBuffer.stable.rawValue
        self.liveBuffer = LiveBuffer(rawValue: rawBuffer) ?? .stable

        // ⚠️ `object(forKey:)` kontrolü şart: `bool(forKey:)` kayıt yokken
        // `false` döner ve iki özellik de kapalı başlardı. Varsayılanları
        // **açık** olmalı.
        self.autoReconnect = store.object(forKey: Keys.autoReconnect) as? Bool ?? true
        self.useFallbackEngine = store.object(forKey: Keys.useFallbackEngine) as? Bool ?? true
    }
}
