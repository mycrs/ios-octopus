import OctopusDomain

/// PiP'in nerede ve nasıl sunulacağını tek yerde tanımlar.
///
/// Film ve bölümlerde kullanıcı açıkça PiP düğmesine basar. Canlı yayınlarda
/// gösterilmez; uygulamadan çıkmak veya oynatıcıyı kapatmak PiP'i kendiliğinden
/// başlatmaz.
public enum PictureInPicturePolicy {

    /// Geri/Home hareketinin videoyu kendiliğinden küçültmesini engeller.
    public static let startsAutomaticallyFromInline = false

    /// Sistem motoru hazırsa yalnızca film ve dizi bölümleri PiP sunar.
    public static func canShowButton(
        for item: PlaybackItem,
        engineIsReady: Bool
    ) -> Bool {
        guard engineIsReady else { return false }

        switch item.source {
        case .movie, .episode:
            return true
        case .liveChannel:
            return false
        }
    }
}
