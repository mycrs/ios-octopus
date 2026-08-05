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

    private let isEnabled: Bool
    private let isUnlocked: Bool

    public init(isEnabled: Bool, isUnlocked: Bool) {
        self.isEnabled = isEnabled
        self.isUnlocked = isUnlocked
    }

    /// Kilit kurulu ve açılmamışsa yetişkin içerik gizlenir.
    public var hidesAdultContent: Bool {
        isEnabled && !isUnlocked
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

    public func filter(_ movies: [Movie]) -> [Movie] {
        guard hidesAdultContent else { return movies }
        return movies.filter { !$0.isAdult }
    }
}
