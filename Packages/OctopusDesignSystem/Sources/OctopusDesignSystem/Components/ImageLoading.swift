import Foundation
import Nuke

/// Görsel yükleme boru hattının ayarı.
///
/// Nuke'un varsayılanları genel amaçlı; IPTV kataloğu ise uç bir durum:
/// tek bir hesapta 20.000 kanal logosu ve on binlerce afiş olabiliyor ve
/// kullanıcı bunları hızla kaydırıyor.
///
/// ⚠️ 3rd-party bağımlılık kuralı: `Nuke` yalnızca bu modülde geçer
/// (bkz. CLAUDE.md, demir kural 4). Uygulama `configure()` çağırır,
/// Nuke'un adını görmez.
public enum ImageLoading {

    /// Açılışta **bir kez** çağrılır.
    public static func configure() {
        let isConstrained = ProcessInfo.processInfo.physicalMemory <= 3 * 1_024 * 1_024 * 1_024
        let memory = ImageCache()
        memory.costLimit = (isConstrained ? 32 : 96) * 1_024 * 1_024
        memory.countLimit = isConstrained ? 128 : 512
        // Nuke bu cache'i bellek uyarısında boşaltır ve arka planda küçültür.
        // Büyük iPad/iPhone RAM'i afişlere sınırsız bütçe vermemeli.
        ImagePipeline.shared = ImagePipeline {
            // Diskte ham baytı sakla: afiş ve logo adresleri sabit,
            // içerikleri değişmez. Varsayılan URLCache yerine Nuke'un
            // kendi deposu kullanılıyor çünkü boyut sınırı ayarlanabiliyor.
            $0 = .withDataCache(
                name: Self.cacheName,
                sizeLimit: (isConstrained ? 128 : 256) * 1_024 * 1_024
            )
            $0.imageCache = memory
            $0.dataLoadingQueue.maxConcurrentOperationCount = isConstrained ? 3 : 4

            // Hem baytı hem çözülmüş görüntüyü sakla. Küçültülmüş afişleri
            // yeniden çözmek CPU yakıyordu.
            $0.dataCachePolicy = .automatic

            // Aşamalı çözme (progressive) kapalı: küçük afişlerde tek
            // kazancı "bulanık önizleme", bedeli her karede yeniden çözme.
            $0.isProgressiveDecodingEnabled = false
        }
    }

    private static let cacheName = "com.octopus.iptv.images"

    /// Kullanıcı önbelleği temizler. Kaynak geçişinde ortak görseller korunur.
    public static func clearCache() {
        ImagePipeline.shared.cache.removeAll()
    }
}
