import Foundation
import AVFoundation
import OctopusCore

/// Ses oturumu yönetimi — arka planda ses, sessize alma anahtarı, kesintiler.
///
/// ## Neden ayrı bir tip?
/// `AVAudioSession` **süreç genelinde tek**tir; her motor kendi başına
/// yapılandırırsa son konuşan kazanır ve davranış motora göre değişir.
/// Burada tek yerden yönetiliyor, iki motor da (AVPlayer, VLC) aynı
/// kuralı paylaşıyor.
///
/// ⚠️ `.playback` kategorisi iki şey yapar: sessize alma anahtarı açıkken
/// bile ses çıkar (video oynatıcıdan beklenen davranış) ve `Info.plist`'teki
/// `UIBackgroundModes: audio` ile birlikte uygulama arka plandayken ses
/// devam eder. Kategori ayarlanmazsa arka plan izni **hiçbir işe yaramaz**.
@MainActor
public final class AudioSessionController {

    /// Kesinti (telefon geldi, başka uygulama sesi aldı) bittiğinde
    /// oynatmaya devam edilmeli mi? Motor bunu dinler.
    public enum Interruption: Equatable, Sendable {
        case began
        case endedShouldResume
        case endedShouldStay
    }

    private let session: AVAudioSession
    private var interruptionObserver: NSObjectProtocol?

    public init(session: AVAudioSession = .sharedInstance()) {
        self.session = session
    }

    /// Oynatma başlamadan **önce** çağrılır.
    ///
    /// Hata yutulmaz ama fırlatılmaz da: ses oturumu kurulamasa bile video
    /// sessiz oynayabilir; kullanıcıya "oynatılamıyor" demek abartı olur.
    public func activate() {
        do {
            // `.moviePlayback` modu AVPlayer'a doğru tamponlama profilini verir.
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true, options: [])
        } catch {
            Log.playback.error("Ses oturumu açılamadı: \(error.localizedDescription)")
        }
    }

    /// Oynatıcı kapanırken çağrılır — sesi başka uygulamalara geri bırakır.
    ///
    /// ⚠️ `notifyOthersOnDeactivation` olmadan, arka planda çalan müzik
    /// uygulaması oynatıcı kapandıktan sonra kendiliğinden devam etmez.
    public func deactivate() {
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            Log.playback.error("Ses oturumu kapatılamadı: \(error.localizedDescription)")
        }
    }

    /// Kesintileri dinlemeye başlar.
    ///
    /// Telefon geldiğinde iOS oynatmayı **kendiliğinden** duraklatır ama
    /// kesinti bitince devam ettirmez; devam kararı uygulamanındır.
    public func observeInterruptions(
        _ handler: @escaping @Sendable @MainActor (Interruption) -> Void
    ) {
        stopObserving()

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { notification in
            // Bildirim gövdesi ana kuyruktan geliyor ama derleyici bunu
            // bilmiyor; izolasyona açıkça geçiliyor.
            let interruption = Self.interpret(notification.userInfo)
            Task { @MainActor in
                guard let interruption else { return }
                handler(interruption)
            }
        }
    }

    public func stopObserving() {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        interruptionObserver = nil
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
    }

    /// Bildirim sözlüğünü karara çevirir — saf fonksiyon, test edilebilir.
    ///
    /// `shouldResume` yalnızca kesinti **bittiğinde** ve sistem izin
    /// verdiğinde gelir. Sistem izin vermediği hâlde oynatmaya devam etmek
    /// (ör. kullanıcı araya başka bir video açtıysa) iki sesin üst üste
    /// binmesi demektir.
    /// - Note: `nonisolated` — bu sınıf `@MainActor`, dolayısıyla statik
    ///   üyeleri de izole olurdu. Bildirim gövdesi (izolasyonsuz bir bağlam)
    ///   buradan çağırıyor; izole kalsaydı derlenmezdi
    ///   (bkz. BRAIN.md § 11.1, aynı tuzak testlerde de yaşandı).
    nonisolated static func interpret(_ userInfo: [AnyHashable: Any]?) -> Interruption? {
        guard
            let rawType = userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else { return nil }

        switch type {
        case .began:
            return .began
        case .ended:
            let rawOptions = userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            return options.contains(.shouldResume) ? .endedShouldResume : .endedShouldStay
        @unknown default:
            return nil
        }
    }
}
