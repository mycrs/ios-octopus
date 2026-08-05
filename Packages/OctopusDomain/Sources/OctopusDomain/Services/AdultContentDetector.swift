import Foundation

/// Yetişkin içeriği ad ve kategoriden tanır.
///
/// Neden gerekli: sağlayıcılardan gelen `is_adult` alanı güvenilmez.
/// M3U listelerinde böyle bir alan **hiç yok**; Xtream panellerinin çoğu da
/// doldurmuyor. Buna karşılık neredeyse hepsi yetişkin içeriği kategori
/// adıyla işaretliyor: "XXX", "ADULT", "+18", "EROTIK"…
///
/// Bu bir **iş kuralıdır**, ayrıştırma detayı değil: "hangi içerik yetişkin
/// sayılır" sorusunun cevabı Domain'de durur, iki parser de buradan okur.
///
/// ⚠️ Hata yönü kasıtlı: şüpheli durumda içerik **gizlenir**. Yanlışlıkla
/// gizlenen bir kanal kullanıcıyı rahatsız eder; yanlışlıkla gösterilen bir
/// yetişkin kanal ebeveyn kilidini anlamsız kılar. İkisi eşit ağırlıkta değil.
public enum AdultContentDetector {

    /// Tam sözcük olarak arandığında yetişkin içeriğe işaret eden damgalar.
    ///
    /// Sözcük sınırına bakılır: "adult" damgası "Adult Swim"i (çizgi film
    /// kanalı) yakalar ama "Adulthood" gibi bir film adını da yakalardı —
    /// bu yüzden liste dar tutuluyor ve başlığa değil **kategoriye** bakılır.
    private static let markers: Set<String> = [
        "xxx", "adult", "adults", "porn", "porno", "sex",
        "erotic", "erotik", "hardcore", "18+", "+18"
    ]

    /// Sözcüğe bölmeden aranan damgalar — bitişik yazılsa da yakalanır.
    ///
    /// "XXX" panellerde "PL|XXX", "TR-XXX24" gibi biçimlerde geçiyor;
    /// sözcük sınırı araması bunları kaçırıyordu.
    private static let embeddedMarkers = ["xxx", "porno", "hardcore"]

    /// Kategori adı yetişkin içeriğe mi işaret ediyor?
    ///
    /// Ölçüt kategoridir, tek tek başlık değil: bir film adında "sex"
    /// geçmesi (ör. "Sex and the City") onu yetişkin içerik yapmaz.
    public static func isAdult(categoryName: String?) -> Bool {
        guard let categoryName else { return false }

        let normalized = normalize(categoryName)
        guard !normalized.isEmpty else { return false }

        if embeddedMarkers.contains(where: { normalized.contains($0) }) { return true }

        // Ayraçlar kategori adlarında bol: "TR | XXX", "VOD-ADULT", "18+ FILM".
        let words = normalized.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "+" })
        return words.contains { markers.contains(String($0)) }
    }

    /// Sağlayıcının bildirdiği bayrak **veya** kategori adı.
    ///
    /// Sağlayıcı "yetişkin" diyorsa tartışılmaz; demiyorsa kategoriye bakılır.
    public static func isAdult(providerFlag: Bool?, categoryName: String?) -> Bool {
        if providerFlag == true { return true }
        return isAdult(categoryName: categoryName)
    }

    /// Küçük harfe indirger ve Türkçe'ye özgü harfleri sadeleştirir.
    ///
    /// ⚠️ `lowercased()` tek başına yetmiyor: Türkçe "I" küçük harfe "ı"
    /// olarak iner ve "XXI" gibi değerlerde beklenmedik sonuç verir.
    /// Damgalar ASCII olduğu için karşılaştırma da ASCII'ye indirgenir.
    private static func normalize(_ raw: String) -> String {
        raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
    }

    // MARK: - Katalog damgalama
    //
    // Senkronizasyon sırasında çağrılır: kategori adları ile içerik orada
    // birleşir. Sağlayıcı bayrağı zaten `true` ise dokunulmaz.

    public static func markAdultContent(
        _ channels: [Channel],
        categories: [MediaCategory]
    ) -> [Channel] {
        let adultCategories = adultCategoryIDs(categories)
        guard !adultCategories.isEmpty else { return channels }

        return channels.map { channel in
            guard !channel.isAdult,
                  let categoryID = channel.categoryID,
                  adultCategories.contains(categoryID)
            else { return channel }

            var marked = channel
            marked.isAdult = true
            return marked
        }
    }

    public static func markAdultContent(
        _ movies: [Movie],
        categories: [MediaCategory]
    ) -> [Movie] {
        let adultCategories = adultCategoryIDs(categories)
        guard !adultCategories.isEmpty else { return movies }

        return movies.map { movie in
            guard !movie.isAdult,
                  let categoryID = movie.categoryID,
                  adultCategories.contains(categoryID)
            else { return movie }

            var marked = movie
            marked.isAdult = true
            return marked
        }
    }

    public static func markAdultContent(
        _ series: [Series],
        categories: [MediaCategory]
    ) -> [Series] {
        let adultCategories = adultCategoryIDs(categories)
        guard !adultCategories.isEmpty else { return series }

        return series.map { item in
            guard !item.isAdult,
                  let categoryID = item.categoryID,
                  adultCategories.contains(categoryID)
            else { return item }

            var marked = item
            marked.isAdult = true
            return marked
        }
    }

    /// Adı yetişkin içeriğe işaret eden kategorilerin kimlikleri.
    private static func adultCategoryIDs(_ categories: [MediaCategory]) -> Set<MediaCategory.ID> {
        Set(categories.filter { isAdult(categoryName: $0.name) }.map(\.id))
    }
}
