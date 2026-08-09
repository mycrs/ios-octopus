import AVKit
import OctopusCore

/// Resim içinde resim (PiP).
///
/// ## Neden ayrı dosya?
/// PiP, `AVKit`'e bağımlı olan **tek** parça. Motorun geri kalanı
/// `AVFoundation` ile yetiniyor; ayrımı görünür tutmak, ileride bu
/// yeteneğin kaldırılmasını ya da başka bir motora taşınmasını kolaylaştırır.
///
/// ⚠️ Simülatörde çalışmaz (`isPictureInPictureSupported() == false`).
/// Bu yüzden hiçbir şey varsayılmıyor: destek yoksa kontrolör hiç
/// kurulmuyor, UI de düğmeyi göstermiyor.
extension AVPlayerEngine {

    /// PiP kontrolörünü verilen katmana bağlar.
    ///
    /// `makeVideoView()` her çağrıldığında yeniden kurulur: PiP bir
    /// **katmana** bağlıdır ve katman değişince eski kontrolör ölü bir
    /// katmanı işaret eder.
    func attachPictureInPicture(to view: PlayerLayerView) {
        pictureInPictureController = nil

        guard
            AVPictureInPictureController.isPictureInPictureSupported(),
            let layer = view.playerLayer
        else { return }

        // ⚠️ Başlatıcı **failable**: katman bir oynatıcıya bağlı değilse
        // ya da sistem PiP'i reddederse `nil` döner. `try!`/force unwrap
        // yasak (CLAUDE.md), zaten burada çökmek de gereksiz — PiP
        // kurulamazsa düğme çıkmaz, oynatma etkilenmez.
        guard let controller = AVPictureInPictureController(playerLayer: layer) else {
            Log.playback.notice("PiP kontrolörü kurulamadı")
            return
        }

        // Kullanıcı uygulamadan çıkınca video kendiliğinden küçük pencereye
        // geçsin — PiP'in beklenen davranışı bu; elle düğmeye basmak değil.
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        pictureInPictureController = controller
    }

    /// PiP şu an başlatılabilir mi?
    ///
    /// Yalnızca "destekleniyor mu" yetmez: video henüz yüklenmemişken
    /// kontrolör hazır değildir ve düğmeye basmak sessizce başarısız olur.
    public var isPictureInPicturePossible: Bool {
        pictureInPictureController?.isPictureInPicturePossible ?? false
    }

    public func setPictureInPictureActive(_ active: Bool) {
        guard let controller = pictureInPictureController else { return }

        if active {
            guard controller.isPictureInPicturePossible else {
                Log.playback.notice("PiP istendi ama şu an mümkün değil")
                return
            }
            controller.startPictureInPicture()
        } else {
            controller.stopPictureInPicture()
        }
    }
}
