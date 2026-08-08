import Foundation
import MediaPlayer
import OctopusCore
import OctopusDomain

/// Kilit ekranı ve denetim merkezi bilgisi.
///
/// Arka planda ses çalarken kullanıcının gördüğü tek arayüz burasıdır:
/// başlık, kapak, ilerleme ve düğmeler. `Info.plist`'teki
/// `UIBackgroundModes: audio` sesin devam etmesini sağlar ama **denetimi
/// sağlamaz** — kilit ekranında düğmeler ancak burası doldurulunca çıkar.
@MainActor
public final class NowPlayingCenter {

    /// Uzak denetimlerin bağlanacağı eylemler.
    ///
    /// Kapanış olarak alınıyor ki bu tip `PlayerController`'ı tanımasın;
    /// tek yönlü bağımlılık test edilebilirliği koruyor.
    public struct Handlers {
        public let play: @MainActor () -> Void
        public let pause: @MainActor () -> Void
        public let skip: @MainActor (TimeInterval) -> Void
        public let seek: @MainActor (TimeInterval) -> Void

        public init(
            play: @escaping @MainActor () -> Void,
            pause: @escaping @MainActor () -> Void,
            skip: @escaping @MainActor (TimeInterval) -> Void,
            seek: @escaping @MainActor (TimeInterval) -> Void
        ) {
            self.play = play
            self.pause = pause
            self.skip = skip
            self.seek = seek
        }
    }

    private let infoCenter: MPNowPlayingInfoCenter
    private let commandCenter: MPRemoteCommandCenter
    private var artworkTask: Task<Void, Never>?
    private var artworkURL: URL?

    public init(
        infoCenter: MPNowPlayingInfoCenter = .default(),
        commandCenter: MPRemoteCommandCenter = .shared()
    ) {
        self.infoCenter = infoCenter
        self.commandCenter = commandCenter
    }

    // MARK: - Denetimler

    /// Uzak denetimleri bağlar.
    ///
    /// ⚠️ Canlı yayında sarma ve konum değiştirme **kapatılır**: kilit
    /// ekranında çalışmayan düğme göstermek, kullanıcının uygulamayı
    /// bozuk sanmasına yol açar.
    public func attach(handlers: Handlers, isLive: Bool) {
        detachCommands()

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { _ in
            handlers.play()
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { _ in
            handlers.pause()
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true

        commandCenter.skipForwardCommand.isEnabled = !isLive
        commandCenter.skipForwardCommand.preferredIntervals = [10]
        commandCenter.skipForwardCommand.addTarget { event in
            guard let skipEvent = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            handlers.skip(skipEvent.interval)
            return .success
        }

        commandCenter.skipBackwardCommand.isEnabled = !isLive
        commandCenter.skipBackwardCommand.preferredIntervals = [10]
        commandCenter.skipBackwardCommand.addTarget { event in
            guard let skipEvent = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            handlers.skip(-skipEvent.interval)
            return .success
        }

        commandCenter.changePlaybackPositionCommand.isEnabled = !isLive
        commandCenter.changePlaybackPositionCommand.addTarget { event in
            guard let seekEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            handlers.seek(seekEvent.positionTime)
            return .success
        }
    }

    // MARK: - Bilgi

    /// Kilit ekranı bilgisini tazeler.
    ///
    /// ⚠️ `elapsedPlaybackTime` her saniye yazılmaz: sistem `playbackRate`
    /// üzerinden kendi ilerletir. Sık yazmak hem pahalı hem de kilit
    /// ekranındaki çubuğun titremesine yol açar — yalnızca durum
    /// değiştiğinde ve aramadan sonra çağrılmalıdır.
    public func update(item: PlaybackItem, time: PlaybackTime, isPlaying: Bool, rate: Float) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: time.current,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? rate : 0,
            MPNowPlayingInfoPropertyIsLiveStream: item.isLive
        ]

        if let subtitle = item.subtitle, !subtitle.isEmpty {
            info[MPMediaItemPropertyArtist] = subtitle
        }

        // Canlıda süre yazılmaz: sistem 0 uzunluklu bir çubuk çizerdi.
        if let duration = time.duration, duration > 0, !item.isLive {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }

        // Var olan kapak korunur; her tazelemede yeniden indirilmesin.
        if let existing = infoCenter.nowPlayingInfo?[MPMediaItemPropertyArtwork] {
            info[MPMediaItemPropertyArtwork] = existing
        }

        infoCenter.nowPlayingInfo = info
        loadArtworkIfNeeded(item.artworkURL)
    }

    /// Kapağı arka planda indirir.
    ///
    /// Nuke kullanılmıyor: o bağımlılık DesignSystem'e hapsedildi
    /// (bkz. CLAUDE.md demir kural 4) ve oynatma katmanı UI paketlerini
    /// import edemez. Tek bir görsel için `URLSession` fazlasıyla yeterli.
    private func loadArtworkIfNeeded(_ url: URL?) {
        guard let url, url != artworkURL else { return }
        artworkURL = url

        artworkTask?.cancel()
        artworkTask = Task { [weak self] in
            guard
                let (data, _) = try? await URLSession.shared.data(from: url),
                let image = UIImage(data: data),
                !Task.isCancelled
            else { return }

            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self?.setArtwork(artwork)
        }
    }

    private func setArtwork(_ artwork: MPMediaItemArtwork) {
        guard var info = infoCenter.nowPlayingInfo else { return }
        info[MPMediaItemPropertyArtwork] = artwork
        infoCenter.nowPlayingInfo = info
    }

    // MARK: - Temizlik

    /// Oynatıcı kapanırken çağrılır.
    ///
    /// ⚠️ Atlanırsa kilit ekranında **çalmayan** bir içerik görünmeye
    /// devam eder ve düğmeleri ölü bir oynatıcıya gider.
    public func clear() {
        artworkTask?.cancel()
        artworkTask = nil
        artworkURL = nil
        detachCommands()
        infoCenter.nowPlayingInfo = nil
    }

    private func detachCommands() {
        // `addTarget` her çağrıda yeni bir dinleyici ekler; kaldırılmazsa
        // ikinci oynatmada her düğme iki kez tetiklenir.
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.skipForwardCommand.removeTarget(nil)
        commandCenter.skipBackwardCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)
    }
}
