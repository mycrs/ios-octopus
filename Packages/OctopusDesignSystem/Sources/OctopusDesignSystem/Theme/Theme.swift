import SwiftUI

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
        public static let background = Color(hex: 0x1C1B1F)
        public static let surface = Color(hex: 0x2B2930)
        public static let surfaceElevated = Color(hex: 0x36333D)

        /// Marka rengi. Faz 3'te kullanıcı seçimi ve bayi paneli bunu ezebilecek.
        public static let accent = Color(hex: 0x00B0FF)
        public static let accentMuted = Color(hex: 0x00B0FF).opacity(0.16)

        public static let textPrimary = Color(hex: 0xE6E1E5)
        public static let textSecondary = Color(hex: 0x938F99)
        public static let textTertiary = Color(hex: 0x6B6672)

        public static let separator = Color(hex: 0x3A3740)

        public static let live = Color(hex: 0xFF4D4F)
        public static let success = Color(hex: 0x00E676)
        public static let warning = Color(hex: 0xFF9100)
        public static let error = Color(hex: 0xF2B8B5)
    }

    /// Kullanıcının Ayarlar'dan seçebileceği marka renkleri.
    ///
    /// Faz 3'te `ThemeController` bunları uygulayacak; şu an yalnızca
    /// tasarım kararı olarak sabitlendi.
    public enum BrandColor: String, CaseIterable, Sendable {
        case `default`
        case purple
        case green
        case orange

        public var color: Color {
            switch self {
            case .default: return Palette.accent
            case .purple: return Color(hex: 0xE040FB)
            case .green: return Color(hex: 0x00E676)
            case .orange: return Color(hex: 0xFF9100)
            }
        }
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
