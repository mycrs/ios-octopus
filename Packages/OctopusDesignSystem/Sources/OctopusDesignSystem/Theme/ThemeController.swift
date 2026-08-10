import SwiftUI
import Combine
import OctopusDomain

/// Uygulamanın marka rengini yönetir.
///
/// ## Öncelik sırası
/// 1. **Kullanıcı seçimi** — Ayarlar'dan bilinçli olarak seçilmişse her şeyi ezer
/// 2. **Bayi paneli** — kullanıcı "Varsayılan"daysa panelin rengi uygulanır
/// 3. **Uygulama varsayılanı** — `#00B0FF`
///
/// Bu sıra Android sürümüyle aynı: bayi markasını uygulamak istiyoruz ama
/// kullanıcının kendi tercihini de ezmemeliyiz.
@MainActor
public final class ThemeController: ObservableObject {

    /// Kullanıcının Ayarlar'dan seçtiği renk.
    @Published public private(set) var selection: Theme.BrandColor
    /// Panelden gelen marka rengi (doğrulanmış).
    @Published public private(set) var remoteColor: Color?
    /// Bayi adı — karşılama ve ayarlar ekranında gösterilebilir.
    @Published public private(set) var resellerName: String?
    /// Bayi logosu — yoksa görünümler uygulamanın kendi işaretini kullanır.
    @Published public private(set) var logoURL: URL?

    private let store: UserDefaults
    private static let selectionKey = "theme.brandColor"

    public init(store: UserDefaults = .standard) {
        self.store = store
        let raw = store.string(forKey: Self.selectionKey) ?? Theme.BrandColor.default.rawValue
        self.selection = Theme.BrandColor(rawValue: raw) ?? .default
    }

    /// Uygulanacak vurgu rengi.
    public var accent: Color {
        // Kullanıcı bilinçli bir renk seçtiyse panel onu ezemez.
        if selection != .default { return selection.color }
        return remoteColor ?? Theme.Palette.accent
    }

    /// Kullanıcı Ayarlar'dan renk seçti.
    public func select(_ color: Theme.BrandColor) {
        selection = color
        store.set(color.rawValue, forKey: Self.selectionKey)
    }

    /// Panel yapılandırması geldi.
    ///
    /// Geçersiz veya "seçilmemiş" sayılan renkler (bkz.
    /// `BrandConfiguration.effectiveColorHex`) burada zaten elenmiş olur.
    public func apply(branding: BrandConfiguration?) {
        resellerName = branding?.resellerName
        logoURL = branding?.logoURL
        // `effectiveColorHex` zaten doğrulanmış ve "seçilmemiş" sayılan
        // renkleri elemiş olarak gelir.
        remoteColor = branding?.effectiveColorHex.flatMap { Color(hexString: $0) }
    }
}

// MARK: - Ortam değeri
//
// Doğrudan `Theme.Palette.accent` yerine bu değeri kullanan görünümler
// bayi rengine uyum sağlar. `tint` mirası çoğu kontrolü zaten kapsar;
// bu değer ikon ve çizim gibi tint almayan yerler içindir.

private struct BrandColorKey: EnvironmentKey {
    static let defaultValue = Theme.Palette.accent
}

extension EnvironmentValues {
    public var brandColor: Color {
        get { self[BrandColorKey.self] }
        set { self[BrandColorKey.self] = newValue }
    }
}
