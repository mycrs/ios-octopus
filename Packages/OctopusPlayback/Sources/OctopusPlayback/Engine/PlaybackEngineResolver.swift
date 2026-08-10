import Foundation
import OctopusDomain

/// Hangi motorun kullanılacağına karar verir.
///
/// **Yedek motor opsiyoneldir.** `fallback` verilmezse uygulama yalnızca
/// AVPlayer ile çalışır ve yine de derlenir/çalışır. VLCKit entegrasyonu
/// bozulsa bile uygulama ayakta kalır — izolasyonun asıl kazancı budur.
@MainActor
public struct PlaybackEngineResolver {

    public typealias EngineFactory = () -> PlaybackEngine

    /// Seçim sonucu — saf ve test edilebilir olsun diye motordan ayrı tutuldu.
    public enum Decision: String, Equatable, Sendable {
        /// AVPlayer: sistem entegrasyonu tam (PiP, AirPlay, arka plan sesi).
        case native
        /// VLC: geniş format desteği.
        case fallback
    }

    private let makeNative: EngineFactory
    private let makeFallback: EngineFactory?

    public init(native: @escaping EngineFactory, fallback: EngineFactory? = nil) {
        self.makeNative = native
        self.makeFallback = fallback
    }

    public var hasFallback: Bool { makeFallback != nil }

    /// Saf karar fonksiyonu — motor örneği oluşturmaz, bu yüzden test edilebilir.
    ///
    /// Kural:
    /// 1. AVPlayer formatı destekliyorsa onu kullan (daha iyi sistem entegrasyonu).
    /// 2. Desteklemiyorsa ve yedek varsa yedeğe git.
    /// 3. Yedek yoksa yine de AVPlayer'ı dene — açılmama ihtimali var ama
    ///    kullanıcıya "motor yok" demekten iyidir.
    public func decide(
        for format: StreamFormat,
        allowingFallback: Bool = true
    ) -> Decision {
        if format.isNativelySupported { return .native }
        return hasFallback && allowingFallback ? .fallback : .native
    }

    /// Karara göre motor üretir.
    public func makeEngine(
        for format: StreamFormat,
        allowingFallback: Bool = true
    ) -> PlaybackEngine {
        switch decide(for: format, allowingFallback: allowingFallback) {
        case .native:
            return makeNative()
        case .fallback:
            return makeFallback?() ?? makeNative()
        }
    }

    /// Native motor içeriği açamadığında çağrılır (çalışma zamanı fallback).
    ///
    /// `unknown` formatlı akışlarda ilk deneme AVPlayer'la yapılır; 403/codec
    /// hatası gelirse `PlayerController` buraya düşer ve VLC ile yeniden dener.
    /// Yedek yoksa `nil` döner ve hata kullanıcıya gösterilir.
    public func makeRuntimeFallbackEngine() -> PlaybackEngine? {
        makeFallback?()
    }

    /// Bu format için çalışma zamanında yeniden deneme mantıklı mı?
    ///
    /// Zaten yedek motordaysak veya yedek yoksa tekrar denemenin anlamı yok.
    public func canRetryWithFallback(after decision: Decision) -> Bool {
        decision == .native && hasFallback
    }
}
