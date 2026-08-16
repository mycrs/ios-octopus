import Foundation
import Combine

/// Uygulamanın görünür dil tercihi.
///
/// `system`, cihaz Türkçe kullanıyorsa Türkçeyi; diğer tüm cihaz dillerinde
/// İngilizceyi seçer. Böylece desteklenmeyen bir cihaz dilinde Türkçe metinlere
/// düşülmez.
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case turkish
    case english

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: return "Sistem"
        case .turkish: return "Türkçe"
        case .english: return "English"
        }
    }
}

/// `String` olarak taşınan kullanıcı metinlerini seçili SwiftUI diline göre
/// çözer. İçerik adı gibi çeviri anahtarı olmayan değerler aynen döner.
public enum AppLocalization {
    public static func localized(
        _ key: String,
        locale: Locale,
        _ arguments: CVarArg...
    ) -> String {
        localized(key, locale: locale, arguments: arguments)
    }

    public static func localized(
        _ key: String,
        locale: Locale,
        arguments: [CVarArg]
    ) -> String {
        let isTurkish = locale.identifier.lowercased().hasPrefix("tr")
        let format: String

        if isTurkish {
            format = key
        } else if
            let path = Bundle.main.path(forResource: "en", ofType: "lproj"),
            let bundle = Bundle(path: path)
        {
            let resolved = bundle.localizedString(forKey: key, value: key, table: nil)
            if resolved == key, let dynamic = localizedEnglishDynamic(
                key,
                bundle: bundle,
                locale: locale
            ) {
                return dynamic
            }
            format = resolved
        } else {
            format = key
        }

        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: locale, arguments: arguments)
    }

    /// Ters-ayrıştırmadan çıkan argüman. `CVarArg` `Equatable` olmadığı için
    /// testlerde karşılaştırılamıyordu; bu sarmalayıcı onu mümkün kılıyor.
    enum FormatArgument: Equatable {
        case number(Int)
        case text(String)

        var cVarArg: CVarArg {
            switch self {
            case .number(let value): return value
            case .text(let value): return value
            }
        }
    }

    /// Biçimlenmiş bir metinden çeviri anahtarını ve argümanlarını geri çıkarır.
    ///
    /// ⚠️ **Saf fonksiyon** — paket, dil, hiçbir I/O yok. Ayrılmasının sebebi
    /// test edilebilirlik: eşleme mantığı `Bundle` okumasıyla iç içeydi ve
    /// `Bundle.main` paket testinde uygulama paketi olmadığı için bu 130 satır
    /// hiç test edilememişti.
    ///
    /// Asıl çözüm bu ters-ayrıştırmayı hiç yapmamak olurdu: ViewModel'ler
    /// biçimlenmiş Türkçe metin yerine anahtar + argüman taşısaydı. O gün
    /// gelene kadar en azından davranış kilitli.
    static func dynamicFormat(for key: String) -> (formatKey: String, arguments: [FormatArgument])? {
        let singleNumberPatterns: [(suffix: String, formatKey: String)] = [
            (" dakika önce güncellendi", "%ld dakika önce güncellendi"),
            (" saat önce güncellendi", "%ld saat önce güncellendi"),
            (" gün önce güncellendi", "%ld gün önce güncellendi"),
            (" dakika önce", "%ld dakika önce"),
            (" saat önce", "%ld saat önce"),
            (" gün önce", "%ld gün önce"),
            (" gün kaldı", "%ld gün kaldı"),
            (" bölüm", "%ld bölüm"),
            (" sezon", "%ld sezon"),
            (" dk", "%ld dk"),
            (" sa", "%ld sa")
        ]

        for pattern in singleNumberPatterns where key.hasSuffix(pattern.suffix) {
            let rawNumber = key.dropLast(pattern.suffix.count)
            guard let number = Int(rawNumber) else { continue }
            return (pattern.formatKey, [.number(number)])
        }

        let spacedDuration = key.split(separator: " ")
        if
            spacedDuration.count == 4,
            spacedDuration[1] == "sa",
            spacedDuration[3] == "dk",
            let hours = Int(spacedDuration[0]),
            let minutes = Int(spacedDuration[2])
        {
            return ("%ld sa %ld dk", [.number(hours), .number(minutes)])
        }

        if key.hasSuffix("dk") {
            let withoutMinutes = key.dropLast(2)
            if let minute = Int(withoutMinutes) {
                return ("%ld dk", [.number(minute)])
            }

            let parts = withoutMinutes.split(separator: "s", maxSplits: 1)
            if
                parts.count == 2,
                let hours = Int(parts[0]),
                let minutes = Int(String(parts[1]).trimmingCharacters(in: .whitespaces))
            {
                return ("%ld sa %ld dk", [.number(hours), .number(minutes)])
            }
        }

        let numberedTrackPatterns: [(prefix: String, formatKey: String)] = [
            ("Ses ", "Ses %ld"),
            ("Altyazı ", "Altyazı %ld")
        ]

        for pattern in numberedTrackPatterns where key.hasPrefix(pattern.prefix) {
            guard let number = Int(key.dropFirst(pattern.prefix.count)) else { continue }
            return (pattern.formatKey, [.number(number)])
        }

        if key.hasSuffix(". Sezon"), let season = Int(key.dropLast(". Sezon".count)) {
            return ("%ld. Sezon", [.number(season)])
        }

        let suffixPatterns: [(suffix: String, formatKey: String)] = [
            (" — devam et", "%@ — devam et"),
            (" oynat", "%@ oynat"),
            (" · Seçili", "%@ · Seçili"),
            (", canlı yayın", "%@, canlı yayın")
        ]

        for pattern in suffixPatterns where key.hasSuffix(pattern.suffix) {
            let value = String(key.dropLast(pattern.suffix.count))
            return (pattern.formatKey, [.text(value)])
        }

        let prefixPatterns: [(prefix: String, formatKey: String)] = [
            ("Oynatılıyor: ", "Oynatılıyor: %@"),
            ("Puan ", "Puan %@")
        ]

        for pattern in prefixPatterns where key.hasPrefix(pattern.prefix) {
            let value = String(key.dropFirst(pattern.prefix.count))
            return (pattern.formatKey, [.text(value)])
        }

        return nil
    }

    /// Saf eşlemeyi paket okumasıyla birleştiren ince katman.
    private static func localizedEnglishDynamic(
        _ key: String,
        bundle: Bundle,
        locale: Locale
    ) -> String? {
        guard let match = dynamicFormat(for: key) else { return nil }
        return formatted(
            match.formatKey,
            bundle: bundle,
            locale: locale,
            arguments: match.arguments.map(\.cVarArg)
        )
    }

    private static func formatted(
        _ key: String,
        bundle: Bundle,
        locale: Locale,
        arguments: [CVarArg]
    ) -> String {
        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        return String(format: format, locale: locale, arguments: arguments)
    }
}

/// Cihaz dili ile kullanıcının Ayarlar seçimini tek noktada birleştirir.
@MainActor
public final class LanguageController: ObservableObject {
    @Published public private(set) var selection: AppLanguage

    private let store: UserDefaults
    private let preferredLanguages: () -> [String]
    private static let selectionKey = "language.selection"

    public init(
        store: UserDefaults = .standard,
        preferredLanguages: @escaping () -> [String] = { Locale.preferredLanguages }
    ) {
        self.store = store
        self.preferredLanguages = preferredLanguages

        let saved = store.string(forKey: Self.selectionKey)
            .flatMap(AppLanguage.init(rawValue:))
        selection = saved ?? .system
    }

    public var resolvedLanguageCode: String {
        switch selection {
        case .turkish:
            return "tr"
        case .english:
            return "en"
        case .system:
            let deviceLanguage = preferredLanguages().first?.lowercased() ?? "en"
            return deviceLanguage.hasPrefix("tr") ? "tr" : "en"
        }
    }

    public var locale: Locale {
        Locale(identifier: resolvedLanguageCode)
    }

    public var resolvedLanguageTitle: String {
        resolvedLanguageCode == "tr" ? "Türkçe" : "English"
    }

    public func select(_ language: AppLanguage) {
        guard selection != language else { return }
        selection = language
        store.set(language.rawValue, forKey: Self.selectionKey)
    }

    /// `String` olarak taşınan sunum metinlerini de elle seçilen dile çevirir.
    /// SwiftUI'ın sabit metinleri kökte verilen `Locale` ile kendisi çözer.
    public func localized(_ key: String, _ arguments: CVarArg...) -> String {
        AppLocalization.localized(key, locale: locale, arguments: arguments)
    }
}
