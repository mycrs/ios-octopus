import Foundation
import UIKit
import OctopusDomain

/// Video oynatma motoru sözleşmesi.
///
/// İki implementasyonu vardır:
/// - `AVPlayerEngine`      (bu modülde)      — HLS/MP4, PiP + AirPlay + arka plan sesi
/// - `VLCPlaybackEngine`   (OctopusPlaybackVLC) — MPEG-TS/MKV/RTSP
///
/// ⚠️ `FeaturePlayer` hangi motorun çalıştığını **bilmez**. Sadece bu protokole bakar.
/// Yeni bir motor eklemek (ör. FFmpeg) = yeni bir dosya; UI'da tek satır değişmez.
///
/// `@MainActor`: motorlar UIKit katmanı (`AVPlayerLayer`, `VLCVideoView`) yönetir;
/// bunlara ana iş parçacığı dışından dokunmak çökme sebebidir.
@MainActor
public protocol PlaybackEngine: AnyObject {

    /// Motorun kimliği — loglama ve hata ayıklama için.
    var identifier: String { get }

    /// Durum/zaman/iz olayları. Tüketici tek bir `for await` döngüsüyle dinler.
    var events: AsyncStream<PlaybackEvent> { get }

    var currentState: PlaybackState { get }
    var audioTracks: [MediaTrack] { get }
    var subtitleTracks: [MediaTrack] { get }

    /// Şu an çalan izler.
    ///
    /// ⚠️ Seçim yalnızca kullanıcı `select(track:)` çağırdığında değişmez:
    /// sistem, cihaz diline ve erişilebilirlik ayarlarına göre açılışta
    /// kendisi bir iz seçer. Menüde işaretli satırı göstermek için motorun
    /// **gerçek** seçimini sormak gerekir, en son ne istediğimizi değil.
    var selectedAudioTrack: MediaTrack? { get }
    var selectedSubtitleTrack: MediaTrack? { get }

    /// AVPictureInPicture desteği. VLC için `false`.
    var supportsPictureInPicture: Bool { get }

    /// AirPlay ile yayınlanabilir mi?
    ///
    /// ⚠️ Motora bağlı: AVPlayer sistem route'unu kullanır ve videoyu
    /// Apple TV'ye gönderir; VLC kendi çözdüğü kareleri ekrana çizdiği
    /// için yalnızca ses gider. Düğmeyi motor desteklemiyorken göstermek,
    /// çalışmayan bir özellik vaat etmek olur.
    var supportsAirPlay: Bool { get }

    /// İçeriği yükler. Otomatik oynatmaz — `play()` çağrılmalıdır.
    func load(_ item: PlaybackItem) async

    func play()
    func pause()
    func stop()

    /// Canlı yayında motor bunu yok sayabilir.
    func seek(to seconds: TimeInterval) async

    func setVolume(_ volume: Float)
    func setRate(_ rate: Float)

    func select(track: MediaTrack)

    /// Görüntünün çerçeveye yerleşimi. Motor desteklemiyorsa yok sayabilir.
    func setVideoFit(_ fit: VideoFit)

    /// Video katmanını taşıyan UIKit görünümü.
    /// SwiftUI tarafında `VideoSurfaceView` (UIViewRepresentable) ile sarılır.
    func makeVideoView() -> UIView

    /// Kaynakları serbest bırakır. Ekran kapanırken çağrılması **zorunludur** —
    /// aksi halde IPTV bağlantı kotası (`connectionLimitReached`) dolar.
    func teardown()
}

/// Bir motorun hangi formatları açabildiğini bildirir.
public protocol PlaybackEngineDescriptor: Sendable {
    /// Bu motor verilen formatı açabilir mi?
    func canPlay(_ format: StreamFormat) -> Bool
    /// Hiçbir motor iddia etmezse son çare olarak kullanılsın mı?
    var isUniversalFallback: Bool { get }
}
