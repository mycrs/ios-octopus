import Foundation

/// Kanal adından "bu yayın AVPlayer'ı zorlayacak" tahmini.
///
/// **Neden isme bakıyoruz?** Codec'i kesin öğrenmenin tek yolu akışı açıp
/// bakmak. Bu, panelde ikinci bir bağlantı demek — IPTV panelleri eşzamanlı
/// oturumu sınırlar ve yoklama yüzünden asıl oynatma "bağlantı sınırı"
/// hatası alabilir. Yani kesinlik uğruna oynatmayı riske atmak olurdu.
///
/// İsim ipucu bedava ve bu alanda şaşırtıcı derecede güvenilir: paneller
/// kanalları "TR: TRT 1 UHD H265", "4K | Sinema" gibi adlandırır.
///
/// ⚠️ **Sadece bir tahmin.** Yanılırsa maliyeti tek seferlik: kanal
/// gereksiz yere VLC'de açılır (PiP/AirPlay kaybı) ya da AVPlayer denenip
/// ~800 ms sonra yedeğe düşülür. İkisi de kurtarılabilir; bu yüzden
/// eşik dar tutuldu — şüphede kalınca AVPlayer denensin.
public enum HighEfficiencyHint {

    /// ⚠️ Dar liste bilinçli. "HD" veya "FHD" **yok**: onlar H.264 olabilir
    /// ve listeye girerse katalogun yarısı gereksiz yere VLC'ye giderdi —
    /// tam da kaçındığımız sonuç.
    private static let markers = [
        "hevc", "h265", "h.265", "x265", "uhd", "4k", "2160"
    ]

    /// Bu ad, AVPlayer'ın açamayacağı bir yayına mı işaret ediyor?
    public static func suggestsFallbackEngine(title: String) -> Bool {
        let haystack = title.lowercased()
        return markers.contains { containsAsWord($0, in: haystack) }
    }

    /// İşaret, adda **kelime olarak** geçiyor mu?
    ///
    /// ⚠️ Tüm geçişlere bakılıyor, yalnızca ilkine değil. Önce sadece ilk
    /// eşleşme kontrol ediliyordu ve "24 Kanal 4K" gibi bir adda baştaki
    /// sahte "4k" gerçek olanı gölgeliyordu: kanal ipucunu kaybediyordu.
    private static func containsAsWord(_ marker: String, in haystack: String) -> Bool {
        var searchStart = haystack.startIndex
        while let range = haystack.range(
            of: marker,
            range: searchStart..<haystack.endIndex
        ) {
            if hasWordBoundaries(around: range, in: haystack) { return true }
            searchStart = haystack.index(after: range.lowerBound)
        }
        return false
    }

    private static func hasWordBoundaries(
        around range: Range<String.Index>,
        in haystack: String
    ) -> Bool {
        let before = range.lowerBound == haystack.startIndex
            ? nil
            : haystack[haystack.index(before: range.lowerBound)]
        guard !isWordCharacter(before) else { return false }

        guard range.upperBound < haystack.endIndex else { return true }
        let after = haystack[range.upperBound]
        guard isWordCharacter(after) else { return true }

        // ⚠️ Tek istisna: çözünürlük eki. "2160p" ve "2160i" alanın en
        // yaygın yazımı; harf komşusu diye elenirse ipucu işe yaramaz.
        // Ek yalnızca rakamla biten işaretlerde ve tek harf olarak kabul
        // edilir — "2160pixel" yine eşleşmez.
        guard marker(range, in: haystack).last?.isNumber == true,
              after == "p" || after == "i" else { return false }
        let afterSuffix = haystack.index(after: range.upperBound)
        return afterSuffix == haystack.endIndex
            || !isWordCharacter(haystack[afterSuffix])
    }

    private static func marker(_ range: Range<String.Index>, in haystack: String) -> String {
        String(haystack[range])
    }

    private static func isWordCharacter(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character.isLetter || character.isNumber
    }
}
