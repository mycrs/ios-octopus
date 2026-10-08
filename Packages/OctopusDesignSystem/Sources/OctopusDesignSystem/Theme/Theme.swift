import SwiftUI
import UIKit

/// Tasarım sabitleri. Ekranlarda **ham değer yazılmaz** — hepsi buradan gelir.
///
/// Sebep: "şu ekranda köşe yuvarlaklığı 12, diğerinde 14" kaymasını
/// baştan imkânsız kılmak. Tema değişikliği tek dosyadan yapılır.
public enum Theme {

    // MARK: - Renk
    //
    // IPTV arayüzleri koyu temada yaşar: video kenarında açık arayüz
    // göz yorar ve poster/logo renklerini bozar. Bu yüzden koyu esastır.
    //
    // Palet, Android sürümüyle aynı görsel kimliği taşır —
    // bkz. Docs/REFERANS-ANALIZI.md § 1.

    public enum Palette {
        public static let background = Color(hex: 0x091525)
        public static let surface = Color(hex: 0x11263B)
        public static let surfaceElevated = Color(hex: 0x19374F)

        /// Ortak ürün mavisi. Panel verisi uygulamanın görsel kimliğini değiştirmez.
        public static let accent = Color(hex: 0x00B0FF)
        public static let accentMuted = Color(hex: 0x00B0FF).opacity(0.16)

        public static let textPrimary = Color(hex: 0xFFFFFF)
        public static let textSecondary = Color(hex: 0x9CB3CB)
        public static let textTertiary = Color(hex: 0x9CB3CB)

        public static let separator = Color(hex: 0x294660)

        public static let live = Color(hex: 0xFF4D4F)
        public static let success = Color(hex: 0x00E676)
        public static let warning = Color(hex: 0xFF9100)
        public static let error = Color(hex: 0xF2B8B5)
    }

    /// Kullanıcının Ayarlar'dan seçebileceği marka renkleri.
    ///
    /// Eski kayıt anahtarları korunur; renkler mavi ailesine taşınmıştır.
    public enum BrandColor: String, CaseIterable, Sendable {
        case `default`
        case purple
        case green
        case orange

        public var title: String {
            switch self {
            case .default: return "Mavi"
            case .purple: return "Okyanus"
            case .green: return "Turkuaz"
            case .orange: return "Gök mavisi"
            }
        }

        public var color: Color {
            switch self {
            case .default: return Palette.accent
            case .purple: return Color(hex: 0x4596FF)
            case .green: return Color(hex: 0x22D3EE)
            case .orange: return Color(hex: 0x38BDF8)
            }
        }
    }

    /// Black or white text chosen by actual sRGB contrast, for the selected accent.
    public static func contentColor(on color: Color) -> Color {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return Palette.textPrimary
        }
        func linear(_ value: CGFloat) -> Double {
            let channel = Double(value)
            return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        return luminance > 0.179 ? .black : .white
    }

    // MARK: - Aralık (4pt ızgara)

    public enum Spacing {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
    }

    // MARK: - Yerleşim payları

    public enum Layout {
        /// Sekme çubuğunun kaydırılabilir içeriğin son satırını örtmemesi için
        /// bırakılan pay.
        ///
        /// ⚠️ Altı kök ekranda `56` sabiti tek tek yazılıydı; biri değişse
        /// diğerleri sessizce ayrı düşerdi. Push edilen ekranlarda (Ayarlar,
        /// detaylar, liste yöneticisi) ise hiç yoktu — bkz. `Docs/BRAIN.md`.
        public static let tabBarClearance: CGFloat = 56
    }

    // MARK: - Köşe yarıçapı

    public enum Radius {
        public static let sm: CGFloat = 6
        public static let md: CGFloat = 10
        public static let lg: CGFloat = 16
        public static let pill: CGFloat = 999
    }

    // MARK: - Tipografi
    //
    // Dinamik tip desteklenir: sabit punto YERİNE sistem stilleri kullanılır.

    public enum Typography {
        public static let screenTitle = Font.largeTitle.weight(.bold)
        public static let sectionTitle = Font.title3.weight(.semibold)
        public static let rowTitle = Font.body.weight(.medium)
        public static let rowSubtitle = Font.subheadline
        public static let caption = Font.caption
        public static let badge = Font.caption2.weight(.bold)
    }

    // MARK: - Poster oranları

    public enum AspectRatio {
        /// Film/dizi afişi.
        public static let poster: CGFloat = 2.0 / 3.0
        /// Arka plan görseli / bölüm kapağı.
        public static let backdrop: CGFloat = 16.0 / 9.0
        /// Kanal logosu.
        public static let logo: CGFloat = 1.0
    }
}

extension Color {

    /// `"#RRGGBB"` veya `"RRGGBB"` biçimindeki metinden renk.
    ///
    /// Panelden gelen marka renkleri metin olarak taşınır. Dönüşüm burada
    /// yapılır ki Domain kendi ayrıştırıcısını dışa açmak zorunda kalmasın.
    public init?(hexString: String) {
        var text = hexString.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(hex: value)
    }

    /// `0xRRGGBB` biçiminden renk. Tasarım sabitlerini okunur tutmak için.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
