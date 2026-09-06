import Foundation

/// "Sıradaki bölüm" kartının ne zaman görüneceği kuralı.
///
/// Dizi izlemenin en sık tekrarlanan anı bölümler arası geçiştir; buradaki
/// her saniye doğrudan hissedilir. Kart bitişte değil, **kapanış jeneriği
/// akarken** çıkar: kullanıcı jeneriği sonuna kadar izlemek zorunda kalmaz.
public enum NextEpisodePrompt {

    /// Bitişten kaç saniye önce görünsün.
    ///
    /// Dizilerde kapanış jeneriği tipik olarak 30-60 sn. Daha erken çıkarsa
    /// hâlâ süren sahnenin üstünü kapatır, daha geç çıkarsa kullanıcı zaten
    /// jeneriği baştan sona izlemiş olur.
    public static let leadTime: TimeInterval = 45

    /// ⚠️ Kısa içerikte eşik anlamsız: 3 dakikalık bir bölümde 45 sn,
    /// sürenin dörtte biri eder ve kart neredeyse baştan açık kalırdı.
    public static let minimumDuration: TimeInterval = 5 * 60

    /// Gösterilecek geri sayım, ya da kart görünmeyecekse `nil`.
    ///
    /// ⚠️ Süre `nil` gelebilir — bazı paneller VOD süresini bildirmiyor.
    /// O durumda eşik hesaplanamaz ve çağıran taraf bitişteki davranışa
    /// düşmelidir; burada tahmin üretmek yanlış zamanda kart çıkarırdı.
    public static func countdown(
        currentSeconds: TimeInterval,
        durationSeconds: TimeInterval?
    ) -> Int? {
        guard
            let duration = durationSeconds,
            duration >= minimumDuration
        else { return nil }

        let remaining = duration - currentSeconds
        // Geri sarıldığında da `nil` döner; kart kapanmalı.
        guard remaining > 0, remaining <= leadTime else { return nil }
        return Int(remaining.rounded(.up))
    }
}
