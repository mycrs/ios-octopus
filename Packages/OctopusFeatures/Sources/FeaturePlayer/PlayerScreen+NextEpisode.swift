import SwiftUI
import OctopusDomain
import OctopusPlayback

extension PlayerScreen {

    var presentedNextEpisode: Episode? {
        if let nextEpisode = viewModel.nextEpisode { return nextEpisode }
#if DEBUG
        guard previewsNextEpisodeOverlay else { return nil }
        return Episode(
            id: Episode.ID("preview-next"),
            seriesID: Series.ID("preview-series"),
            seasonNumber: 1,
            number: 2,
            title: "İkinci Bölüm",
            streamKey: "preview"
        )
#else
        return nil
#endif
    }

    var presentedNextEpisodeCountdown: Int? {
        if let nextEpisodeCountdown { return nextEpisodeCountdown }
#if DEBUG
        return previewsNextEpisodeOverlay ? 8 : nil
#else
        return nil
#endif
    }

    /// Konum ilerledikçe bindirmenin çıkma zamanını değerlendirir.
    ///
    /// ⚠️ Önceden kart yalnızca `.ended` geldiğinde çıkıyor, sonra da 8 sn
    /// sayıyordu: kullanıcı jeneriği sonuna kadar izleyip **üstüne** 8 sn
    /// daha bekliyordu. Sıradaki bölüme geçiş dizi izlemenin en sık
    /// tekrarlanan anı; buradaki her saniye doğrudan hissediliyor.
    func updateNextEpisodePrompt(_ time: PlaybackTime) {
        guard
            !didDismissNextEpisode,
            viewModel.nextEpisode != nil,
            nextEpisodeTask == nil
        else { return }

        nextEpisodeCountdown = NextEpisodePrompt.countdown(
            currentSeconds: time.current,
            durationSeconds: time.duration
        )
    }

    func handlePlaybackStateChange(_ state: PlaybackState) {
        guard state == .ended, viewModel.nextEpisode != nil, !didDismissNextEpisode else {
            if state != .ended {
                nextEpisodeTask?.cancel()
                nextEpisodeTask = nil
                nextEpisodeCountdown = nil
            }
            return
        }

        guard nextEpisodeTask == nil else { return }

        // Kart jenerik boyunca zaten görünüyorduysa bekletmenin anlamı yok:
        // kullanıcı geri sayımı izledi, bölüm bitti, doğrudan geçilir.
        if nextEpisodeCountdown != nil {
            playNextEpisodeNow()
            return
        }

        // Süre bilinmiyorsa (bazı paneller VOD süresini vermez) kart hiç
        // çıkmamış olur; o durumda eski davranış korunuyor ve kullanıcıya
        // iptal edecek kadar zaman tanınıyor.
        nextEpisodeCountdown = 8
        nextEpisodeTask = Task { @MainActor in
            for remaining in stride(from: 7, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                nextEpisodeCountdown = remaining
            }
            await viewModel.playNextEpisode()
            nextEpisodeTask = nil
            nextEpisodeCountdown = nil
        }
    }

    func playNextEpisodeNow() {
        nextEpisodeTask?.cancel()
        nextEpisodeTask = nil
        nextEpisodeCountdown = nil
        // Yeni bölüm kendi kartını hak ediyor.
        didDismissNextEpisode = false
        Task { await viewModel.playNextEpisode() }
    }

    func cancelNextEpisode() {
        nextEpisodeTask?.cancel()
        nextEpisodeTask = nil
        nextEpisodeCountdown = nil
        // ⚠️ Bayrak şart: kart artık konuma bağlı çıktığı için, kapatılsa
        // bile bir sonraki konum güncellemesinde (yarım saniye sonra)
        // hemen geri gelirdi. Kullanıcının "hayır" demesi bölüm boyunca
        // geçerli olmalı.
        didDismissNextEpisode = true
        showsControls = true
    }
}
