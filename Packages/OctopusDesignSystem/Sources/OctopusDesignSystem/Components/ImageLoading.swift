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
        ImagePipeline.shared = ImagePipeline {
            // Diskte ham baytı sakla: afiş ve logo adresleri sabit,
            // içerikleri değişmez. Varsayılan URLCache yerine Nuke'un
            // kendi deposu kullanılıyor çünkü boyut sınırı ayarlanabiliyor.
            $0.dataCache = try? DataCache(name: Self.cacheName)

            // Hem baytı hem çözülmüş görüntüyü sakla. Küçültülmüş afişleri
            // yeniden çözmek CPU yakıyordu.
            $0.dataCachePolicy = .automatic

            // Aşamalı çözme (progressive) kapalı: küçük afişlerde tek
            // kazancı "bulanık önizleme", bedeli her karede yeniden çözme.
            $0.isProgressiveDecodingEnabled = false
        }
    }

    private static let cacheName = "com.octopus.iptv.images"

    /// Kullanıcı "önbelleği temizle" derse veya kaynak değişince.
    ///
    /// Kaynak değiştiğinde eski panelin afişleri artık geçersiz; diskte
    /// tutmak yalnızca yer kaplar.
    public static func clearCache() {
        ImagePipeline.shared.cache.removeAll()
    }
}
