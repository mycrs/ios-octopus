import OctopusDomain

/// PiP'in nerede ve nasıl sunulacağını tek yerde tanımlar.
///
/// Film, bölüm ve canlı yayınlarda kullanıcı açıkça PiP düğmesine basar.
/// Uygulamadan çıkmak veya oynatıcıyı kapatmak PiP'i kendiliğinden başlatmaz.
public enum PictureInPicturePolicy {

    /// Geri/Home hareketinin videoyu kendiliğinden küçültmesini engeller.
    public static let startsAutomaticallyFromInline = false

    /// İçerik türünden bağımsız olarak sistem motoru hazırsa PiP sunulur.
    public static func canShowButton(
        for item: PlaybackItem,
        engineIsReady: Bool
    ) -> Bool {
        guard engineIsReady else { return false }

        switch item.source {
        case .liveChannel, .movie, .episode:
            return true
        }
    }
}
