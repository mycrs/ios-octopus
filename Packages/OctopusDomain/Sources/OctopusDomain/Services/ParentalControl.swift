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

    /// PIN doğruysa oturumu açar.
    @discardableResult
    func unlock(with pin: String) async -> Bool

    /// Oturum kilidini tekrar kapatır (uygulama arka plana alınınca).
    func lock() async

    /// Kilidi tamamen kaldırır — doğru PIN gerekir.
    func disable(with pin: String) async throws
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
    @discardableResult public func unlock(with pin: String) async -> Bool { true }
    public func lock() async {}
    public func disable(with pin: String) async throws {}
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

    public init(isEnabled: Bool, isUnlocked: Bool) {
        // `isEnabled` API uyumluluğu için korunuyor. Üretim denetleyicisi
        // PIN kurulmamışken de kilitli başlar; böylece hassas içerik ilk
        // açılışta kısa süreliğine bile görünmez.
        _ = isEnabled
        self.isUnlocked = isUnlocked
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
    }

    public func allows(movie: Movie) -> Bool {
        !(hidesAdultContent && movie.isAdult)
    }

    public func filter(_ channels: [Channel]) -> [Channel] {
        guard hidesAdultContent else { return channels }
        return channels.filter { !$0.isAdult }
    }

    public func allows(series: Series) -> Bool {
        !(hidesAdultContent && series.isAdult)
    }

    public func filter(_ movies: [Movie]) -> [Movie] {
        guard hidesAdultContent else { return movies }
        return movies.filter { !$0.isAdult }
    }

    public func filter(_ series: [Series]) -> [Series] {
        guard hidesAdultContent else { return series }
        return series.filter { !$0.isAdult }
    }

    /// Yetişkin kategorileri şeritten çıkarır.
    ///
    /// İçeriği gizleyip kategoriyi bırakmak iki sorun doğuruyordu: kullanıcı
    /// "XXX" yazan bir sekme görüyordu (kilit varken bile içeriğin varlığı
    /// belli oluyordu) ve dokununca boş liste açılıyordu.
    public func filter(_ categories: [MediaCategory]) -> [MediaCategory] {
        guard hidesAdultContent else { return categories }
        return categories.filter { !AdultContentDetector.isAdult(categoryName: $0.name) }
    }

    /// Kilidin **o anki** durumundan süzgeç üretir.
    ///
    /// Her ekran bu iki soruyu ayrı ayrı sormak yerine burayı çağırır;
    /// biri unutulursa kilit o ekrandan atlatılabilir hale gelirdi.
    public static func current(_ control: ParentalControlling) async -> ParentalFilter {
        ParentalFilter(
            isEnabled: await control.isEnabled(),
            isUnlocked: await control.isUnlocked()
        )
    }

    /// Kilit kurulmamış varsayılan — ekranlar bununla başlar.
    public static let open = ParentalFilter(isEnabled: false, isUnlocked: true)
}
