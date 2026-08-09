import Foundation
import OctopusDomain
import OctopusPlayback

/// VLC motorunun uygulamaya bağlanma noktası.
///
/// ⚠️ TASARIMIN İSPATI:
/// VLCKit yalnızca bu modülde. Kırılırsa `isAvailable`'ı `false` yapmak
/// yeterlidir: `AppContainer` resolver'a yedek motor vermez ve uygulama
/// AVPlayer ile çalışmaya devam eder. Başka hiçbir dosyaya dokunulmaz.
public enum VLCEngineFactory {

    /// VLCKit bu derlemede bağlı mı?
    public static var isAvailable: Bool { true }

    /// Bu motorun açabildiği formatlar — resolver'ın kararını doğrulamak için.
    ///
    /// VLC pratikte her şeyi açar; `unknown` dahil hepsi `true`. Zaten
    /// AVPlayer'ın açamadıkları buraya düşüyor.
    public static func canPlay(_ format: StreamFormat) -> Bool {
        switch format {
        case .mpegTS, .mkv, .avi, .rtsp, .rtmp, .hls, .mp4, .unknown:
            return true
        }
    }

    @MainActor
    public static func makeEngine(preferences: PlaybackPreferences? = nil) -> PlaybackEngine {
        VLCPlaybackEngine(preferences: preferences)
    }
}
