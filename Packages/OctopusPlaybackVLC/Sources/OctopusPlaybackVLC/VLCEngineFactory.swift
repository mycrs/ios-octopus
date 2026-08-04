import Foundation
import OctopusDomain
import OctopusPlayback

/// VLC motorunun uygulamaya bağlanma noktası.
///
/// 🚧 Faz 5: VLCKit paketi `Package.swift`'te açıldığında burada
/// `VLCPlaybackEngine` yazılacak ve `makeEngine` onu döndürecek.
///
/// ⚠️ TASARIMIN İSPATI:
/// Şu anda VLCKit **bağlı değil** ve `isAvailable == false`.
/// `AppContainer` bunu görünce resolver'a yedek motor vermez;
/// uygulama yalnızca AVPlayer ile sorunsuz çalışır.
/// VLCKit ileride sorun çıkarırsa tek yapılacak şey bu bayrağı kapatmaktır —
/// başka hiçbir dosyaya dokunulmaz.
public enum VLCEngineFactory {

    /// VLCKit bu derlemede bağlı mı?
    public static var isAvailable: Bool { false }

    /// Bu motorun açabildiği formatlar — resolver'ın kararını doğrulamak için.
    public static func canPlay(_ format: StreamFormat) -> Bool {
        switch format {
        case .mpegTS, .mkv, .avi, .rtsp, .rtmp, .hls, .mp4, .unknown:
            return true
        }
    }

    /// Faz 5'te gerçek motoru döndürecek.
    /// Şimdilik `isAvailable == false` olduğu için hiç çağrılmaz.
    @MainActor
    public static func makeEngine() -> PlaybackEngine {
        NullPlaybackEngine(identifier: "vlc-placeholder")
    }
}
