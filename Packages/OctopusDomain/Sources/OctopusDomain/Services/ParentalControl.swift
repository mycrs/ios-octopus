import Foundation

/// Ebeveyn kilidi.
///
/// Yetişkin içerik sağlayıcı tarafından `isAdult` bayrağıyla işaretlenir.
/// Kilit açıkken bu içerik listelerden **tamamen gizlenir** — kilitli
/// gösterip merak uyandırmak yerine hiç görünmez.
public protocol ParentalControlling: Sendable {

    /// Kilit kurulu mu?
    func isEnabled() async -> Bool

    /// Oturum içinde kilit geçici olarak açıldı mı?
    ///
    /// Kullanıcı PIN girdikten sonra uygulama kapanana kadar tekrar
    /// sorulmaz; her kanal değişiminde PIN istemek kullanılamaz olurdu.
    func isUnlocked() async -> Bool

    /// Kilidi kurar veya PIN'i değiştirir.
    func setPIN(_ pin: String) async throws

    /// PIN'i değiştirir — mevcut PIN doğrulanmadan yeni PIN kaydedilemez.
    func changePIN(currentPIN: String, newPIN: String) async throws

    /// PIN doğruysa oturumu açar.
    @discardableResult
    func unlock(with pin: String) async -> Bool

    /// Oturum kilidini tekrar kapatır (uygulama arka plana alınınca).
    func lock() async

    /// Kilidi tamamen kaldırır — doğru PIN gerekir.
    func disable(with pin: String) async throws

    /// Kullanıcının özellikle gizlediği kategori anahtarları.
    func hiddenCategoryKeys() async -> Set<String>

    /// Bir kategoriyi tüm katalog yüzeylerinde gizler veya yeniden gösterir.
    func setCategory(_ category: MediaCategory, hidden: Bool) async
}

/// Kilit kurulmamış varsayılan.
///
/// Domain'de tutulur çünkü feature modülleri birbirini import edemez;
/// her birinde ayrı bir "kilit yok" tipi tanımlamak aynı davranışın
/// kopyalanması olurdu.
public struct OpenParentalControl: ParentalControlling {
    public init() {}
    public func isEnabled() async -> Bool { false }
    public func isUnlocked() async -> Bool { true }
    public func setPIN(_ pin: String) async throws {}
    public func changePIN(currentPIN: String, newPIN: String) async throws {}
    @discardableResult public func unlock(with pin: String) async -> Bool { true }
    public func lock() async {}
    public func disable(with pin: String) async throws {}
    public func hiddenCategoryKeys() async -> Set<String> { [] }
    public func setCategory(_ category: MediaCategory, hidden: Bool) async {}
}

/// Ebeveyn kilidi hataları.
public enum ParentalControlError: Error, Equatable, Sendable {
    /// PIN en az 4 haneli olmalı ve yalnızca rakam içermeli.
    case invalidFormat
    /// Girilen PIN yanlış.
    case wrongPIN
    /// Kilit kurulu değil.
    case notConfigured
    case storageFailure
}

extension ParentalControlling {

    /// Basit test/önizleme denetleyicileri için güvenli varsayılan uygulama.
    /// Üretim denetleyicisi aynı davranışı açıkça uygular.
    public func changePIN(currentPIN: String, newPIN: String) async throws {
        guard await unlock(with: currentPIN) else {
            throw ParentalControlError.wrongPIN
        }
        try await setPIN(newPIN)
    }

    public func hiddenCategoryKeys() async -> Set<String> { [] }
    public func setCategory(_ category: MediaCategory, hidden: Bool) async {}

    /// PIN biçim denetimi — kaydetmeden önce.
    ///
    /// Dört haneden kısa PIN'ler kolayca tahmin edilir; harf kabul etmek
    /// sayısal klavye kullanımını bozar.
    public static func normalizePIN(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4, trimmed.count <= 8 else { return nil }
        guard trimmed.allSatisfy(\.isNumber) else { return nil }
        return trimmed
    }
}

/// Kilit durumuna göre içerik süzme.
///
/// Domain'de tutulur: "yetişkin içerik ne zaman görünür" bir **iş kuralıdır**,
/// sunum detayı değil.
public struct ParentalFilter: Sendable {

    private let isUnlocked: Bool
    private let hiddenCategoryKeys: Set<String>

    public init(
        isEnabled: Bool,
        isUnlocked: Bool,
        hiddenCategoryKeys: Set<String> = []
    ) {
        // `isEnabled` API uyumluluğu için korunuyor. Üretim denetleyicisi
        // PIN kurulmamışken de kilitli başlar; böylece hassas içerik ilk
        // açılışta kısa süreliğine bile görünmez.
        _ = isEnabled
        self.isUnlocked = isUnlocked
        self.hiddenCategoryKeys = hiddenCategoryKeys
    }

    /// Açıkça yetki verilmedikçe hassas içerik gizlenir.
    ///
    /// PIN'in henüz belirlenmemiş olması korumayı kapatmaz. Yalnızca
    /// `OpenParentalControl` gibi bilinçli olarak açık bir denetleyici
    /// `isUnlocked == true` döndürerek süzgeci devre dışı bırakabilir.
    public var hidesAdultContent: Bool {
        !isUnlocked
    }

    public func allows(channel: Channel) -> Bool {
        !(hidesAdultContent && channel.isAdult)
            && !isHidden(playlistID: channel.playlistID, kind: .live, categoryID: channel.categoryID)
    }

    public func allows(movie: Movie) -> Bool {
        !(hidesAdultContent && movie.isAdult)
            && !isHidden(playlistID: movie.playlistID, kind: .movie, categoryID: movie.categoryID)
    }

    public func filter(_ channels: [Channel]) -> [Channel] {
        channels.filter { allows(channel: $0) }
    }

    public func allows(series: Series) -> Bool {
        !(hidesAdultContent && series.isAdult)
            && !isHidden(playlistID: series.playlistID, kind: .series, categoryID: series.categoryID)
    }

    public func filter(_ movies: [Movie]) -> [Movie] {
        movies.filter { allows(movie: $0) }
    }

    public func filter(_ series: [Series]) -> [Series] {
        series.filter { allows(series: $0) }
    }

    /// Yetişkin kategorileri şeritten çıkarır.
    ///
    /// İçeriği gizleyip kategoriyi bırakmak iki sorun doğuruyordu: kullanıcı
    /// "XXX" yazan bir sekme görüyordu (kilit varken bile içeriğin varlığı
    /// belli oluyordu) ve dokununca boş liste açılıyordu.
    public func filter(_ categories: [MediaCategory]) -> [MediaCategory] {
        categories.filter { category in
            !isCategoryHidden(category)
                && !(hidesAdultContent && AdultContentDetector.isAdult(categoryName: category.name))
        }
    }

    public func isCategoryHidden(_ category: MediaCategory) -> Bool {
        hiddenCategoryKeys.contains(Self.categoryKey(category))
    }

    public static func categoryKey(_ category: MediaCategory) -> String {
        categoryKey(
            playlistID: category.playlistID,
            kind: category.kind,
            categoryID: category.id
        )
    }

    private static func categoryKey(
        playlistID: Playlist.ID,
        kind: MediaCategory.Kind,
        categoryID: MediaCategory.ID
    ) -> String {
        "\(playlistID.value)|\(kind.rawValue)|\(categoryID.value)"
    }

    private func isHidden(
        playlistID: Playlist.ID,
        kind: MediaCategory.Kind,
        categoryID: MediaCategory.ID?
    ) -> Bool {
        guard let categoryID else { return false }
        return hiddenCategoryKeys.contains(
            Self.categoryKey(playlistID: playlistID, kind: kind, categoryID: categoryID)
        )
    }

    /// Kilidin **o anki** durumundan süzgeç üretir.
    ///
    /// Her ekran bu iki soruyu ayrı ayrı sormak yerine burayı çağırır;
    /// biri unutulursa kilit o ekrandan atlatılabilir hale gelirdi.
    public static func current(_ control: ParentalControlling) async -> ParentalFilter {
        ParentalFilter(
            isEnabled: await control.isEnabled(),
            isUnlocked: await control.isUnlocked(),
            hiddenCategoryKeys: await control.hiddenCategoryKeys()
        )
    }

    /// Kilit kurulmamış varsayılan — ekranlar bununla başlar.
    public static let open = ParentalFilter(isEnabled: false, isUnlocked: true)
}
